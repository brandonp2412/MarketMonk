part of '../charts_page.dart';

extension _ChartFavoriteLoading on ChartsPageState {
  /// Refresh only the visible chart. Updating every holding and every
  /// favorite's ten-year history during a pull can take minutes on mobile.
  /// The cached chart remains visible while refreshes finish in the background.
  Future<void> _refreshCurrentChart() async {
    if (!mounted || !widget.isActive || _networkLoading) return;
    if (_mode == _ChartMode.stock && _selectedSymbol != null) {
      await _loadSelectedStock(forceRefresh: true);
      return;
    }
    if (_mode != _ChartMode.portfolio) return;

    if (_portfolioRefreshInFlight != null) {
      talker.info('Portfolio refresh already in progress; skipping duplicate');
      return;
    }

    // A warm chart is already valid for display. Waiting for fresh snapshots
    // from IBKR and the selected favorites' price providers makes a pull feel
    // like a stalled local cache read even though the chart never disappeared.
    // Keep the refresh asynchronous and publish the refreshed values when
    // their own network calls finish. Only an empty chart needs to wait.
    final hasVisibleHistory = !_periodTransition &&
        _portfolioSeriesByAccount.values.any((series) => series.isNotEmpty);
    _updateState(() => _networkLoading = true);
    final elapsed = Stopwatch()..start();
    talker.info('Portfolio refresh started for visible chart');
    late final Future<void> refresh;
    refresh = Future.wait<void>([
      _loadAllPortfolios(
        refreshIbkrPortfolio: true,
        forceIbkrPortfolioRefresh: true,
        refreshIbkrPerformance: true,
        forceIbkrPerformanceRefresh: true,
      ),
      if (_selectedFavorites.isNotEmpty)
        _syncFavoriteCandles(forceRefresh: true, selectedOnly: true),
    ]).then<void>((_) {}).catchError((Object error, StackTrace stackTrace) {
      talker.handle(error, stackTrace, 'Portfolio refresh failed');
    }).whenComplete(() {
      if (identical(_portfolioRefreshInFlight, refresh)) {
        _portfolioRefreshInFlight = null;
      }
      talker.info(
        'Portfolio refresh network finished after '
        '${elapsed.elapsedMilliseconds}ms',
      );
      if (mounted) _updateState(() => _networkLoading = false);
    });
    _portfolioRefreshInFlight = refresh;

    if (hasVisibleHistory) {
      // The pull indicator represents a request to refresh, not the duration
      // of the broker's work. The existing chart remains on screen throughout.
      talker.info(
        'Portfolio refresh gesture released using cached chart after '
        '${elapsed.elapsedMilliseconds}ms',
      );
      return;
    }

    await refresh.timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        talker.warning('Uncached portfolio refresh exceeded 6s');
        if (mounted) _updateState(() => _networkLoading = false);
      },
    );
  }

  Future<void> _loadFavorites() async {
    final prefs = await SqliteSettings.getInstance();
    var favorites = prefs.getStringList('favoriteStocks');
    if (favorites == null) {
      final legacy = prefs.getString('favoriteStock');
      favorites = legacy != null ? [legacy] : [];
      await prefs.setStringList('favoriteStocks', favorites);
      if (legacy != null) await prefs.remove('favoriteStock');
    }
    if (mounted) {
      _updateState(() {
        _favoriteStocks = favorites!;
        _favoriteNames = {
          for (final symbol in favorites)
            if (prefs.getString('favoriteName:$symbol') case final String name)
              symbol: name,
        };
      });
    }
  }

  Future<void> _syncFavoriteCandles({
    bool forceRefresh = false,
    bool selectedOnly = false,
  }) async {
    final generation = _favoriteLoadGeneration;
    final symbols = _favoriteStocks
        .where((symbol) => !selectedOnly || _selectedFavorites.contains(symbol))
        .toList(growable: false);

    if (!mounted || !widget.isActive || generation != _favoriteLoadGeneration)
      return;
    await Future.wait(
      symbols.map(
        (symbol) => _syncFavoriteCandle(symbol, forceRefresh: forceRefresh),
      ),
    );
  }

  Future<void> _syncFavoriteCandle(
    String symbol, {
    bool forceRefresh = false,
  }) async {
    if (!mounted || !widget.isActive) return;
    final generation = _favoriteLoadGeneration;
    final selectedDays = days;
    final intraday = _usesIntraday && _selectedFavorites.contains(symbol);
    try {
      final accountManager = context.read<AccountManager>();
      if (intraday) {
        final series = await _withRemoteLoading(
          () => _intradayData.fetch(
            symbol,
            days: selectedDays,
            config: accountManager.ibkrConfigFor(),
            forceRefresh: forceRefresh,
            brokerTimeout: const Duration(seconds: 2),
          ),
        );
        if (!mounted ||
            !widget.isActive ||
            generation != _favoriteLoadGeneration) return;
        await fetchSymbolCurrencyAndRate(symbol, rawCurrency: series.currency);
        if (!mounted ||
            !widget.isActive ||
            generation != _favoriteLoadGeneration) return;
        requireUsdRate(symbolCurrency(symbol));
        _updateState(() {
          _favoriteIntraday[symbol] = series;
          _favoriteIntradayErrors.remove(symbol);
        });
        return;
      }
      final previousSync = _favoriteDailySync;
      final sync = previousSync.then((_) async {
        if (!mounted ||
            !widget.isActive ||
            generation != _favoriteLoadGeneration) return;
        try {
          await _withRemoteLoading(
            () =>
                widget._favoriteHistoryPrefetcher?.call(
                  symbol,
                  _requiredCandleStart(),
                ) ??
                syncCandles(
                  symbol,
                  ibkrConfig: accountManager.ibkrConfigFor(),
                  syncNamespace: accountManager.activeAccount,
                  requiredFrom: _requiredCandleStart(),
                  forceRefresh: forceRefresh,
                ),
          );
        } finally {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      });
      _favoriteDailySync = sync.catchError((Object _) {});
      await sync;
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Favorite ticker candle sync failed');
      if (intraday &&
          mounted &&
          widget.isActive &&
          generation == _favoriteLoadGeneration) {
        _updateState(() => _favoriteIntradayErrors[symbol] = error.toString());
      }
    }
  }

  Future<void> _toggleFavorite(String symbol) async {
    final ctx = context;
    final prefs = await SqliteSettings.getInstance();
    if (!ctx.mounted) return;
    final isFavorite = _favoriteStocks.contains(symbol);
    _updateState(() {
      if (isFavorite) {
        _favoriteStocks.remove(symbol);
        _selectedFavorites.remove(symbol);
      } else {
        _favoriteStocks.add(symbol);
      }
    });
    await prefs.setStringList('favoriteStocks', _favoriteStocks);
    if (!ctx.mounted) return;
    if (isFavorite) return;
    runDetachedTask(
      _syncFavoriteCandle(symbol),
      'Failed to sync favorite ticker candle',
    );
  }
}
