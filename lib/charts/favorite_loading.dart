part of '../charts_page.dart';

extension _ChartFavoriteLoading on ChartsPageState {
  /// Syncs candles for all accounts. Caller is responsible for setting
  /// [_networkLoading].
  Future<void> _refreshAllPortfolioCandles({DateTime? requiredFrom}) async {
    if (!mounted || !widget.isActive) return;
    final accountManager = context.read<AccountManager>();

    for (final accountName in accountManager.accounts) {
      if (!mounted || !widget.isActive) return;
      final ibkrConfig = accountManager.ibkrConfigFor(accountName);
      if (ibkrConfig.enabled) continue;

      try {
        final trades = await profileDataRepository.readTradesForAccount(
          accountName,
        );
        if (!mounted || !widget.isActive) return;
        for (final symbol in trades.map((trade) => trade.symbol).toSet()) {
          if (!mounted || !widget.isActive) return;
          await syncCandles(
            symbol,
            ibkrConfig: ibkrConfig,
            syncNamespace: accountName,
            requiredFrom: requiredFrom ?? _requiredCandleStart(),
            forceRefresh: true,
          );
        }
      } catch (error, stackTrace) {
        talker.handle(
          error,
          stackTrace,
          'Portfolio candle refresh failed for $accountName',
        );
      }
    }
  }

  /// A manual refresh warms the largest daily chart range once per favorite.
  /// The persisted candle store is shared by every smaller period (1m–10y).
  /// Bound concurrency to avoid flooding Yahoo or the broker with requests.
  Future<void> _prefetchFavoriteHistory(DateTime from) async {
    final manager = context.read<AccountManager>();
    final config = manager.ibkrConfigFor();
    final namespace = manager.activeAccount;
    final favorites = _favoriteStocks.toSet().toList(growable: false);
    final failed = <String>[];

    for (var offset = 0; offset < favorites.length; offset += 2) {
      final batch = favorites.skip(offset).take(2);
      await Future.wait(
        batch.map((symbol) async {
          try {
            if (widget._favoriteHistoryPrefetcher case final prefetch?) {
              await prefetch(symbol, from);
            } else {
              await syncCandles(
                symbol,
                ibkrConfig: config,
                syncNamespace: namespace,
                requiredFrom: from,
                forceRefresh: true,
              );
            }
          } catch (error, stackTrace) {
            failed.add(symbol);
            talker.handle(
              error,
              stackTrace,
              'Failed to prefetch $symbol history',
            );
          }
        }),
      );
    }
    if (failed.isNotEmpty) {
      talker.warning(
        'Favorite history prefetch failed for: ${failed.join(', ')}',
      );
    }
  }

  /// Refresh portfolio, broker performance and all favorite daily ranges.
  /// Do not finish the gesture until the caches are actually populated.
  Future<void> _refreshCurrentChart() async {
    if (!mounted || !widget.isActive || _networkLoading) return;
    _updateState(() {
      _networkLoading = true;
      _stockError = null;
    });

    try {
      clearAllSyncCache();
      _intradayPortfolioCache.clear();
      _chartPeriodCache.clear();
      _restoredFavoriteCandles = null;
      final now = DateTime.now();
      final historyStart = DateTime(now.year - 10, now.month, now.day - 1);
      await Future.wait([
        _refreshAllPortfolioCandles(requiredFrom: historyStart),
        _prefetchFavoriteHistory(historyStart),
      ]);
      if (!mounted || !widget.isActive) return;
      await _loadAllPortfolios(
        refreshIbkrPortfolio: true,
        forceIbkrPortfolioRefresh: true,
        refreshIbkrPerformance: true,
        forceIbkrPerformanceRefresh: true,
      );
      if (!mounted || !widget.isActive) return;
      if (_usesIntraday && _selectedFavorites.isNotEmpty) {
        await _syncFavoriteCandles(forceRefresh: true, selectedOnly: true);
      }
      if (_mode == _ChartMode.stock && _selectedSymbol != null) {
        await _loadSelectedStock(forceRefresh: true);
      }
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Chart refresh failed');
      if (mounted && _mode == _ChartMode.stock) {
        _updateState(() => _stockError = error.toString());
      }
    } finally {
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
            () => syncCandles(
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
    toast(ctx, ctx.l10n.text('Set as favorite'));
  }
}
