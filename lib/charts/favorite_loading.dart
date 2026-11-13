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

    _updateState(() => _networkLoading = true);
    final elapsed = Stopwatch()..start();
    talker.info('Portfolio refresh started for visible chart');

    late final Future<void> refresh;
    refresh = Future.wait<void>([
      // Force the two broker snapshots and their performance series, but do
      // not re-fetch every position's candle history.
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
    });
    _portfolioRefreshInFlight = refresh;

    try {
      await refresh.timeout(
        const Duration(seconds: 6),
        onTimeout: () => talker.warning(
          'Portfolio refresh exceeded 6s; continuing in background',
        ),
      );
    } finally {
      talker.info(
        'Portfolio refresh gesture completed after '
        '${elapsed.elapsedMilliseconds}ms',
      );
      if (mounted) _updateState(() => _networkLoading = false);
    }
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
