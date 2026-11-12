import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:market_monk/accounts/account_manager.dart';
import 'package:market_monk/adaptive_layout.dart';
import 'package:market_monk/app.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/edit_ticker_page.dart';
import 'package:market_monk/empty_state.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/ibkr_cash.dart';
import 'package:market_monk/ibkr_cash_out_pnl.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/portfolio_allocation.dart';
import 'package:market_monk/profile_data_repository.dart';
import 'package:market_monk/profile_picker.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/ticker_context_actions.dart';
import 'package:market_monk/trade_history_page.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/vi_navigation.dart';
import 'package:provider/provider.dart';

import 'holdings/symbol_summary.dart';

export 'holdings/symbol_summary.dart';

part 'holdings/desktop_holdings.dart';
part 'holdings/holding_tile.dart';
part 'holdings/holdings_loading.dart';

enum _HoldingsSort {
  symbol,
  shares,
  avgCost,
  price,
  value,
  unrealized,
  returnPct,
}

class HoldingsPage extends StatefulWidget {
  final bool isActive;
  final Future<List<Position>> Function(List<Trade>)? _positionsLoader;
  final Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? _ibkrLoader;
  final Future<IbkrTradeHistory> Function(IbkrAccountConfig)?
      _ibkrTradeHistoryLoader;
  const HoldingsPage({
    super.key,
    this.isActive = true,
    Future<List<Position>> Function(List<Trade>)? positionsLoader,
    Future<IbkrPortfolioSnapshot> Function(IbkrAccountConfig)? ibkrLoader,
    Future<IbkrTradeHistory> Function(IbkrAccountConfig)?
        ibkrTradeHistoryLoader,
  })  : _positionsLoader = positionsLoader,
        _ibkrLoader = ibkrLoader,
        _ibkrTradeHistoryLoader = ibkrTradeHistoryLoader;

  @override
  State<HoldingsPage> createState() => HoldingsPageState();
}

class HoldingsPageState extends State<HoldingsPage>
    with AutomaticKeepAliveClientMixin {
  void _updateState(VoidCallback update) => setState(update);

  @override
  bool get wantKeepAlive => true;

  final _search = TextEditingController();
  final _desktopTableScrollController = ScrollController();
  final _desktopTableHorizontalScrollController = ScrollController();
  List<SymbolSummary> _summaries = [];
  // Keep the last complete view for each profile while its stream refreshes.
  final Map<String, List<SymbolSummary>> _profileSummaries = {};
  List<Trade> _ibkrTrades = [];
  Future<List<Trade>>? _ibkrTradesLoad;
  String? _ibkrTradesLoadingAccount;
  String? _ibkrTradesAccount;
  bool _ibkrTradeHistoryAvailable = true;
  late Stream<List<SymbolSummary>> _stream;
  String _lastAccount = '';
  String _lastProfileId = '';
  int _lastIbkrRefreshVersion = -1;
  IbkrAccountConfig _lastIbkrConfig = const IbkrAccountConfig();
  final Map<(String, bool, bool), Future<void>> _preloadLoads = {};
  Object? _preloadError;
  bool _ibkrPreloadCompleted = false;

  bool _selecting = false;
  final Set<String> _selectedSymbols = {};
  SymbolSummary? _desktopHistorySummary;
  _HoldingsSort _desktopSort = _HoldingsSort.value;
  bool _desktopSortAscending = false;
  int _viFocusIndex = -1;
  final _viRowKey = GlobalKey();
  final _searchFocusNode = FocusNode();
  final List<_UndoEntry> _undoStack = [];
  bool _undoInProgress = false;
  late final ViTarget _viTarget = ViTarget(
    requestSearch: () => _requestViSearch(),
    moveFocus: (delta) => _moveViFocus(delta),
    toggleSelect: () => _viToggleSelect(),
    deleteFocus: () => _viDeleteFocus(),
    undoDelete: () => _undoLastDelete(),
    halfPageUp: () => _viScrollHalfPage(up: true),
    halfPageDown: () => _viScrollHalfPage(up: false),
  );

  @override
  void initState() {
    super.initState();
    _stream = _buildStream();
  }

  @override
  void didUpdateWidget(covariant HoldingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncViTarget();
    if (oldWidget.isActive == widget.isActive) return;

    setState(() => _stream = _buildStream());
    if (widget.isActive &&
        context.read<AccountManager>().ibkrConfigFor().enabled) {
      runDetachedTask(_preload(), 'Failed to preload holdings');
    }
  }

  @override
  void dispose() {
    if (ViNavigation.instance.target == _viTarget) {
      ViNavigation.instance.target = null;
    }
    _searchFocusNode.dispose();
    _search.dispose();
    _desktopTableScrollController.dispose();
    _desktopTableHorizontalScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncViTarget();
    final accounts = context.watch<AccountManager>();
    final account = accounts.activeAccount;
    final profileId = accounts.activeProfileId;
    final previousProfileId = _lastProfileId;
    final ibkrConfig = accounts.ibkrConfigFor(account);
    final refreshVersion = accounts.ibkrRefreshVersion;
    final accountChanged = _lastAccount.isNotEmpty && account != _lastAccount;
    final configChanged =
        _lastAccount.isNotEmpty && ibkrConfig != _lastIbkrConfig;
    final refreshRequested =
        _lastAccount.isNotEmpty && refreshVersion != _lastIbkrRefreshVersion;

    if (account == _lastAccount &&
        ibkrConfig == _lastIbkrConfig &&
        refreshVersion == _lastIbkrRefreshVersion) {
      return;
    }

    if (_lastAccount.isEmpty || accountChanged || configChanged) {
      final cachedHistory = accounts.ibkrTradeHistoryCacheFor(account);
      _ibkrTrades = ibkrConfig.enabled && cachedHistory != null
          ? tradesFromIbkr(cachedHistory.trades)
          : [];
      _ibkrTradesAccount =
          ibkrConfig.enabled && accounts.isIbkrTradeHistoryCacheFresh(account)
              ? account
              : null;
      _ibkrTradeHistoryAvailable = cachedHistory?.available ?? true;
    }
    _lastAccount = account;
    _lastProfileId = profileId;
    _lastIbkrConfig = ibkrConfig;
    _lastIbkrRefreshVersion = refreshVersion;
    if (accountChanged ||
        (previousProfileId.isNotEmpty && previousProfileId != profileId)) {
      if (_search.text.isEmpty) {
        _profileSummaries[previousProfileId] = _summaries;
      }
      _search.clear();
      _selectedSymbols.clear();
      _selecting = false;
      _desktopHistorySummary = null;
      _viFocusIndex = -1;
    }
    if (configChanged) _profileSummaries.remove(profileId);
    final cachedPositions = accounts.portfolioCacheFor(account)?.positions;
    final retained =
        accountChanged && !configChanged ? _profileSummaries[profileId] : null;
    setState(() {
      _stream = _buildStream();
      _summaries = retained ??
          (cachedPositions == null
              ? <SymbolSummary>[]
              : _summariesFromPositions(
                  ibkrConfig.enabled ? _ibkrTrades : const <Trade>[],
                  cachedPositions,
                ));
      _ibkrPreloadCompleted = cachedPositions != null;
      _preloadError = null;
    });
    if (widget.isActive && ibkrConfig.enabled) {
      runDetachedTask(
        _preload(
          refreshPortfolio: refreshRequested || configChanged,
          refreshTrades: refreshRequested || configChanged,
        ),
        'Failed to refresh holdings preload',
      );
    }
  }

  @visibleForTesting
  static bool shouldUsePortfolioCache({
    required bool hasCache,
    required bool refreshPortfolio,
    required bool ibkrEnabled,
    required bool ibkrConfigured,
    required bool cacheFresh,
  }) =>
      hasCache &&
      !refreshPortfolio &&
      ibkrEnabled &&
      (cacheFresh || !ibkrConfigured);

  void _onSearchChanged() {
    final accounts = context.read<AccountManager>();
    setState(() {
      if (accounts.ibkrConfigFor().enabled) {
        final positions = accounts.portfolioCacheFor()?.positions;
        if (positions != null) {
          _summaries = _summariesFromPositions(_ibkrTrades, positions);
        }
      } else {
        _stream = _buildStream();
      }
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedSymbols.clear();
    });
  }

  void _toggleHoldingSelection(String symbol) {
    setState(() {
      if (!_selectedSymbols.remove(symbol)) {
        _selectedSymbols.add(symbol);
      }
      _selecting = _selectedSymbols.isNotEmpty;
    });
  }

  void _toggleSelectAll() {
    final visibleSymbols = _summaries.map((summary) => summary.symbol).toSet();
    if (visibleSymbols.isEmpty) return;
    setState(() {
      if (_selectedSymbols.containsAll(visibleSymbols)) {
        _selectedSymbols.removeAll(visibleSymbols);
      } else {
        _selectedSymbols.addAll(visibleSymbols);
      }
      _selecting = _selectedSymbols.isNotEmpty;
    });
  }

  Future<void> _copySelectedSymbols() async {
    if (_selectedSymbols.isEmpty) return;
    final symbols = _selectedSymbols.toList()..sort();
    await Clipboard.setData(ClipboardData(text: symbols.join('\n')));
    if (mounted) {
      toast(
        context,
        context.l10n.text('Copied {count} symbols', {'count': symbols.length}),
      );
    }
  }

  Future<void> _deleteSelected(
    BuildContext context, {
    Set<String>? symbols,
  }) async {
    final targets = Set<String>.of(symbols ?? _selectedSymbols);
    if (targets.isEmpty ||
        context.read<AccountManager>().ibkrConfigFor().enabled) {
      return;
    }

    final count = targets.length;
    final canUndo =
        isDesktopLayout(context) && context.read<SettingsState>().viModeEnabled;
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
          'be deleted. ${canUndo ? 'Use your Undo shortcut to restore them '
              'before closing the app.' : 'This cannot be undone.'}',
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

    final accountName = context.read<AccountManager>().activeAccount;
    final profileId = await profileDataRepository.profileIdForName(accountName);
    final allTrades = await profileDataRepository.readTrades(profileId);
    final deleted =
        allTrades.where((trade) => targets.contains(trade.symbol)).toList();
    await profileDataRepository.deleteTradesForSymbols(profileId, targets);
    _exitSelecting();
    if (deleted.isNotEmpty) {
      _undoStack.add(_UndoEntry(profileId, deleted));
      if (_undoStack.length > 10) _undoStack.removeAt(0);
    }
    if (ctx.mounted)
      toast(
        ctx,
        context.l10n.text(
          count == 1 ? 'Deleted {count} holding' : 'Deleted {count} holdings',
          {'count': count},
        ),
      );
  }

  List<String> get _viSymbols => _sortDesktopSummaries(_summaries)
      .map((summary) => summary.symbol)
      .toList();

  void _syncViTarget() {
    if (widget.isActive && isDesktopLayout(context)) {
      ViNavigation.instance.target = _viTarget;
    } else if (ViNavigation.instance.target == _viTarget) {
      ViNavigation.instance.target = null;
    }
  }

  void _requestViSearch() {
    _searchFocusNode.requestFocus();
    _search.selection = TextSelection.collapsed(offset: _search.text.length);
  }

  void _moveViFocus(int delta) {
    final symbols = _viSymbols;
    if (symbols.isEmpty) return;
    setState(() {
      _viFocusIndex = viFocusIndex(_viFocusIndex, delta, symbols.length);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _viRowKey.currentContext;
      if (rowContext == null) return;
      ViNavigation.instance.focusedContext.value = rowContext;
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
      );
    });
  }

  void _viToggleSelect() {
    final symbols = _viSymbols;
    if (_viFocusIndex < 0 || _viFocusIndex >= symbols.length) return;
    _toggleHoldingSelection(symbols[_viFocusIndex]);
  }

  void _viDeleteFocus() {
    final symbols = _viSymbols;
    if (_viFocusIndex < 0 || _viFocusIndex >= symbols.length) return;
    final symbol = symbols[_viFocusIndex];
    unawaited(
      _deleteSelected(
        context,
        symbols: _selectedSymbols.contains(symbol) ? null : {symbol},
      ),
    );
  }

  void _viScrollHalfPage({required bool up}) {
    if (!_desktopTableScrollController.hasClients) return;
    final position = _desktopTableScrollController.position;
    final step = position.viewportDimension / 2;
    final offset = (up ? position.pixels - step : position.pixels + step)
        .clamp(0.0, position.maxScrollExtent);
    position.animateTo(
      offset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _undoLastDelete() async {
    if (_undoStack.isEmpty || _undoInProgress) return;
    _undoInProgress = true;
    final entry = _undoStack.last;
    try {
      await profileDataRepository.addTrades(
        entry.profileId,
        entry.trades
            .map(
              (trade) => ProfileTradeWrite(
                symbol: trade.symbol,
                name: trade.name,
                quantity: trade.quantity,
                price: trade.price,
                tradeType: trade.tradeType,
                tradeDate: trade.tradeDate,
                realizedPL: trade.realizedPL,
                commission: trade.commission,
                rawCurrency: trade.rawCurrency,
                usdRateAtTrade: trade.usdRateAtTrade,
                brokerConid: trade.brokerConid,
              ),
            )
            .toList(),
      );
      _undoStack.removeLast();
      if (mounted) {
        toast(
          context,
          context.l10n.text('Restored {count} trades', {
            'count': entry.trades.length,
          }),
        );
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Failed to undo holdings delete');
      if (mounted) toast(context, 'Could not restore trades. Try undo again.');
    } finally {
      _undoInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    context.select<SettingsState, bool>(
      (settings) => settings.hideDollarAmounts,
    );

    final desktop = isDesktopLayout(context);
    final accounts = context.watch<AccountManager>();
    final summary = _desktopHistorySummary;
    if (desktop && summary != null) {
      return TradeHistoryPage(
        key: ValueKey(
          'holdings-history-${accounts.activeAccount}-${summary.symbol}',
        ),
        summary: summary,
        ibkrTradeHistoryLoader: widget._ibkrTradeHistoryLoader,
        onClose: () => setState(() => _desktopHistorySummary = null),
      );
    }
    final ibkrManaged = accounts.ibkrConfigFor().enabled;
    final allSelected = _summaries.isNotEmpty &&
        _selectedSymbols.containsAll(
          _summaries.map((summary) => summary.symbol),
        );

    final menuButton = PopupMenuButton<String>(
      key: const Key('holdings-menu-button'),
      icon: const Icon(Icons.more_vert),
      tooltip: context.l10n.text('Show menu'),
      onSelected: accounts.switchAccount,
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: _summaries.isNotEmpty,
          onTap: _toggleSelectAll,
          child: ListTile(
            leading: Icon(
              allSelected ? Icons.deselect : Icons.done_all_rounded,
            ),
            title: Text(
              allSelected
                  ? context.l10n.text('Deselect all')
                  : context.l10n.text('Select all'),
            ),
          ),
        ),
        if (_selecting) ...[
          PopupMenuItem<String>(
            onTap: _copySelectedSymbols,
            child: ListTile(
              leading: const Icon(Icons.copy),
              title: Text(context.l10n.text('Copy selected')),
            ),
          ),
          if (!ibkrManaged)
            PopupMenuItem<String>(
              onTap: () => _deleteSelected(context),
              child: ListTile(
                leading: const Icon(Icons.delete),
                title: Text(context.l10n.text('Delete selected')),
              ),
            ),
          PopupMenuItem<String>(
            onTap: _exitSelecting,
            child: ListTile(
              leading: const Icon(Icons.close),
              title: Text(context.l10n.text('Cancel selection')),
            ),
          ),
        ],
        const PopupMenuDivider(),
        if (accounts.accounts.length > 1) ...[
          ...accounts.accounts.map(
            (account) => CheckedPopupMenuItem<String>(
              value: account,
              checked: account == accounts.activeAccount,
              child: Text(account),
            ),
          ),
        ],
      ],
    );

    final leading = _selecting
        ? IconButton(
            key: const Key('holdings-clear-selection-button'),
            onPressed: _exitSelecting,
            tooltip: context.l10n.text('Cancel selection'),
            icon: const Icon(Icons.clear),
            padding: const EdgeInsets.only(left: 16, right: 8),
          )
        : _search.text.isEmpty
            ? const Padding(
                padding: EdgeInsets.only(left: 16, right: 8),
                child: Icon(Icons.search),
              )
            : IconButton(
                onPressed: () {
                  _search.clear();
                  _onSearchChanged();
                },
                icon: const Icon(Icons.arrow_back),
                padding: const EdgeInsets.only(left: 16, right: 8),
              );

    if (desktop) {
      final openCount =
          _summaries.where((summary) => summary.position != null).length;
      return DesktopContextMenu(
        actions: [
          DesktopMenuAction(
            context.l10n.text('Refresh'),
            () => runDetachedTask(
              _refreshCandles(),
              'Failed to refresh holdings',
            ),
            icon: Icons.refresh_rounded,
          ),
          if (!ibkrManaged)
            DesktopMenuAction(
              context.l10n.text('Add trade'),
              () => Navigator.push(
                context,
                adaptivePageRoute(
                  context,
                  builder: (_) => const EditTickerPage(),
                ),
              ),
              icon: Icons.add_rounded,
            ),
        ],
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 64,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const ProfilePicker(key: Key('holdings-profile-picker')),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${accounts.activeAccount} · ${context.l10n.text('Holdings')}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$openCount open · ${_summaries.length} total symbols',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      if (_selecting) ...[
                        SizedBox(
                          width: 150,
                          child: TextButton.icon(
                            onPressed: _toggleSelectAll,
                            icon: Icon(
                              allSelected
                                  ? Icons.deselect
                                  : Icons.done_all_rounded,
                            ),
                            label: Text(
                              allSelected
                                  ? context.l10n.text('Deselect all')
                                  : context.l10n.text('Select all'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _copySelectedSymbols,
                          icon: const Icon(Icons.copy_rounded),
                          label: Text(context.l10n.text('Copy symbols')),
                        ),
                        if (!ibkrManaged) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 150,
                            child: FilledButton.tonalIcon(
                              onPressed: () => _deleteSelected(context),
                              icon: const Icon(Icons.delete_outline),
                              label: Text(
                                context.l10n.text('Delete ({count})', {
                                  'count': _selectedSymbols.length,
                                }),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _exitSelecting,
                          tooltip: context.l10n.text('Cancel selection'),
                          icon: const Icon(Icons.close),
                        ),
                      ] else if (!ibkrManaged) ...[
                        FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            adaptivePageRoute(
                              context,
                              builder: (_) => const EditTickerPage(),
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: Text(context.l10n.text('Add trade')),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocusNode,
                      onChanged: (_) => _onSearchChanged(),
                      decoration: InputDecoration(
                        hintText: context.l10n.text('Search...'),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_search.text.isNotEmpty)
                              IconButton(
                                onPressed: () {
                                  _search.clear();
                                  _onSearchChanged();
                                },
                                icon: const Icon(Icons.close),
                              ),
                            IconButton(
                              key: const Key('desktop-holdings-refresh'),
                              tooltip: context.l10n.text('Refresh'),
                              onPressed: _refreshCandles,
                              icon: const Icon(Icons.refresh_rounded),
                            ),
                          ],
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
                    key: ValueKey(
                      'holdings-${accounts.activeAccount}-$ibkrManaged',
                    ),
                    stream: _stream,
                    builder: _buildList,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DesktopContextMenu(
      actions: [
        DesktopMenuAction(
          context.l10n.text('Refresh'),
          () =>
              runDetachedTask(_refreshCandles(), 'Failed to refresh holdings'),
          icon: Icons.refresh_rounded,
        ),
        if (!ibkrManaged)
          DesktopMenuAction(
            context.l10n.text('Add trade'),
            () => Navigator.push(
              context,
              adaptivePageRoute(
                context,
                builder: (_) => const EditTickerPage(),
              ),
            ),
            icon: Icons.add_rounded,
          ),
      ],
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                child: SearchBar(
                  controller: _search,
                  hintText: _selecting
                      ? context.l10n.text('{count} selected', {
                          'count': _selectedSymbols.length,
                        })
                      : context.l10n.text('Search...'),
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.only(right: 8),
                  ),
                  leading: leading,
                  onTap: () => _search.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _search.text.length,
                  ),
                  onChanged: (_) => _onSearchChanged(),
                  trailing: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, animation) => ScaleTransition(
                        scale: animation,
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      ),
                      child: _selecting && !ibkrManaged
                          ? IconButton(
                              key: const Key('holdings-delete-button'),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: context.l10n.text('Delete selected'),
                              onPressed: () => _deleteSelected(context),
                            )
                          : IconButton(
                              key: const Key('holdings-settings-button'),
                              icon: const Icon(Icons.settings_outlined),
                              tooltip: context.l10n.text('Settings'),
                              onPressed: () => openAppSettings(context),
                            ),
                    ),
                    menuButton,
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<SymbolSummary>>(
                  key: ValueKey(
                    'holdings-${accounts.activeAccount}-$ibkrManaged',
                  ),
                  stream: _stream,
                  builder: _buildList,
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: switch (true) {
          _ when ibkrManaged => null,
          _ when _selecting => Padding(
              padding: const EdgeInsets.only(bottom: bottomNavHeight),
              child: FloatingActionButton.extended(
                onPressed: () => _deleteSelected(context),
                label: Text(
                  context.l10n.text('Delete ({count})', {
                    'count': _selectedSymbols.length,
                  }),
                ),
                icon: const Icon(Icons.delete),
              ),
            ),
          _ => Padding(
              padding: const EdgeInsets.only(bottom: bottomNavHeight),
              child: FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  adaptivePageRoute(
                    context,
                    builder: (_) => const EditTickerPage(),
                  ),
                ),
                label: Text(context.l10n.text('Add')),
                icon: const Icon(Icons.add),
                tooltip: context.l10n.text('Add trade'),
              ),
            ),
        },
      ),
    );
  }

  List<SymbolSummary> _sortDesktopSummaries(List<SymbolSummary> summaries) {
    final sorted = [...summaries];
    int compare(SymbolSummary a, SymbolSummary b) {
      if (_desktopSort != _HoldingsSort.symbol) {
        if (a.position == null) return b.position == null ? 0 : 1;
        if (b.position == null) return -1;
      }

      final comparison = switch (_desktopSort) {
        _HoldingsSort.symbol => a.symbol.compareTo(b.symbol),
        _HoldingsSort.shares => a.position!.netShares.compareTo(
            b.position!.netShares,
          ),
        _HoldingsSort.avgCost => a.position!.avgCost.compareTo(
            b.position!.avgCost,
          ),
        _HoldingsSort.price => a.position!.currentPrice.compareTo(
            b.position!.currentPrice,
          ),
        _HoldingsSort.value => a.position!.currentValue.compareTo(
            b.position!.currentValue,
          ),
        _HoldingsSort.unrealized => a.position!.unrealizedPL.compareTo(
            b.position!.unrealizedPL,
          ),
        _HoldingsSort.returnPct => a.position!.change.compareTo(
            b.position!.change,
          ),
      };
      return switch (true) {
        _ when comparison == 0 => a.symbol.compareTo(b.symbol),
        _ when _desktopSortAscending => comparison,
        _ => -comparison,
      };
    }

    sorted.sort(compare);
    return sorted;
  }

  Widget _refreshableState(Widget child) {
    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: _refreshCandles,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [SliverFillRemaining(child: child)],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    AsyncSnapshot<List<SymbolSummary>> snap,
  ) {
    if (snap.hasError || _preloadError != null) {
      return _refreshableState(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.text('Couldn’t load holdings')),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _retryHoldings,
                icon: const Icon(Icons.refresh),
                label: Text(context.l10n.text('Try again')),
              ),
            ],
          ),
        ),
      );
    }

    final ibkrManaged = context.watch<AccountManager>().ibkrConfigFor().enabled;
    final summaries = ibkrManaged ? _summaries : snap.data ?? _summaries;
    final cashBalance = ibkrManaged
        ? context.watch<AccountManager>().portfolioCacheFor()?.cashBalance
        : null;
    final cashMatches = _search.text.trim().isEmpty ||
        'cash'.contains(_search.text.trim().toLowerCase());
    final showCash = cashBalance != null && cashMatches;
    final cash = ibkrManaged
        ? _cashAllocation(
            context.read<AccountManager>(),
            summaries
                .where((summary) => summary.position != null)
                .map((summary) => summary.position!),
          )
        : null;

    if (ibkrManaged &&
        summaries.isEmpty &&
        cashBalance == null &&
        _ibkrTrades.isEmpty &&
        !_ibkrPreloadCompleted &&
        !snap.hasData) {
      return _refreshableState(
        const Center(child: CircularProgressIndicator()),
      );
    }

    if (!ibkrManaged && snap.hasData && snap.data != _summaries) {
      final accountName = context.read<AccountManager>().activeAccount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            context.read<AccountManager>().activeAccount == accountName) {
          setState(() => _summaries = snap.data!);
        }
      });
    }

    if (summaries.isEmpty && !showCash) {
      final query = _search.text.trim();
      return _refreshableState(
        AppEmptyState(
          icon: switch (true) {
            _ when ibkrManaged => Icons.account_balance_rounded,
            _ when query.isEmpty => Icons.candlestick_chart_rounded,
            _ => Icons.search_off_rounded,
          },
          title: switch (true) {
            _ when ibkrManaged => context.l10n.text('No IBKR stocks found'),
            _ when query.isEmpty => context.l10n.text('No stocks yet'),
            _ => context.l10n.text('No matching stocks'),
          },
          message: switch (true) {
            _ when ibkrManaged => context.l10n.text(
                'Refresh your portfolio or check your Interactive Brokers connection.',
              ),
            _ when query.isEmpty => context.l10n.text(
                'Import a CSV or add your first trade manually.',
              ),
            _ => context.l10n.text(
                'Nothing matches “{query}”. You can add that ticker now.',
                {'query': query},
              ),
          },
          actionLabel: switch (true) {
            _ when ibkrManaged => context.l10n.text('IBKR settings'),
            _ when query.isEmpty => context.l10n.text('Import CSV'),
            _ => context.l10n.text('Add {symbol}', {
                'symbol': query.toUpperCase(),
              }),
          },
          actionIcon: switch (true) {
            _ when ibkrManaged => Icons.settings_rounded,
            _ when query.isEmpty => Icons.upload_file_rounded,
            _ => Icons.add_rounded,
          },
          onAction: () {
            if (ibkrManaged || query.isEmpty) {
              openAppSettings(context);
            } else {
              Navigator.push(
                context,
                adaptivePageRoute(
                  context,
                  builder: (_) => EditTickerPage(symbol: query.toUpperCase()),
                ),
              );
            }
          },
        ),
      );
    }

    if (isDesktopLayout(context)) {
      return _buildDesktopHoldings(context, summaries, ibkrManaged);
    }

    return RefreshIndicator(
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      onRefresh: _refreshCandles,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: bottomNavScrollClearance),
        itemCount: summaries.length + 1 + (showCash ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) return const SizedBox(height: 8);
          if (showCash && index == 1) {
            return ListTile(
              key: const Key('holdings-ibkr-cash'),
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Cash'),
              subtitle: Text(
                cash == null
                    ? cashBalance.currency
                    : '${formatCashAllocationPercent(cash.percent)}% allocation',
              ),
              trailing: Text(
                formatIbkrReportedCash(cashBalance),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            );
          }
          final summary = summaries[index - (showCash ? 2 : 1)];
          return DesktopContextMenu(
            actionsBuilder: () => _holdingActions(summary, ibkrManaged),
            child: _SymbolTile(
              summary: summary,
              selecting: _selecting,
              isSelected: _selectedSymbols.contains(summary.symbol),
              onTap: () {
                if (_selecting) {
                  _toggleHoldingSelection(summary.symbol);
                } else {
                  _openDetail(summary);
                }
              },
              onLongPress: () {
                if (!_selectedSymbols.contains(summary.symbol)) {
                  _toggleHoldingSelection(summary.symbol);
                }
              },
            ),
          );
        },
      ),
    );
  }

  Future<List<DesktopMenuAction>> _holdingActions(
    SymbolSummary summary,
    bool ibkrManaged,
  ) =>
      tickerContextActions(
        context,
        summary.symbol,
        extraActions: [
          DesktopMenuAction(
            context.l10n.text('Trade History'),
            () => _openDetail(summary),
            icon: Icons.history_rounded,
          ),
          if (!ibkrManaged) ...[
            DesktopMenuAction(
              context.l10n.text('Delete'),
              () => runDetachedTask(
                _deleteSelected(context, symbols: {summary.symbol}),
                'Failed to delete holding',
              ),
              icon: Icons.delete_rounded,
            ),
            DesktopMenuAction(
              context.l10n.text(
                _selectedSymbols.contains(summary.symbol)
                    ? 'Deselect holding'
                    : 'Select holding',
              ),
              () => _toggleHoldingSelection(summary.symbol),
              icon: _selectedSymbols.contains(summary.symbol)
                  ? Icons.indeterminate_check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
            ),
          ],
        ],
      );

  void _openDetail(SymbolSummary s) {
    if (isDesktopLayout(context)) {
      setState(() => _desktopHistorySummary = s);
      return;
    }
    unawaited(
      Navigator.push(
        context,
        adaptivePageRoute(
          context,
          builder: (_) => TradeHistoryPage(
            summary: s,
            ibkrTradeHistoryLoader: widget._ibkrTradeHistoryLoader,
          ),
        ),
      ),
    );
  }

  void _retryHoldings() {
    setState(() {
      _preloadError = null;
      _stream = _buildStream();
    });
    runDetachedTask(_preload(), 'Failed to retry holdings preload');
  }

  Future<void> _refreshCandles() async {
    final accountManager = context.read<AccountManager>();
    final config = accountManager.ibkrConfigFor();
    clearAllSyncCache();
    await _preload(refreshPortfolio: true, refreshTrades: config.enabled);

    if (!config.enabled) {
      final symbols = _summaries.map((summary) => summary.symbol).toSet();
      for (final symbol in symbols) {
        await syncCandles(
          symbol,
          ibkrConfig: config,
          syncNamespace: accountManager.activeAccount,
        );
      }
    }
    if (!mounted || !widget.isActive) return;
  }
}

class _UndoEntry {
  _UndoEntry(this.profileId, this.trades);

  final String profileId;
  final List<Trade> trades;
}
