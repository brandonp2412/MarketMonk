part of '../charts_page.dart';

extension _ChartStockLoading on ChartsPageState {
  void _onSearchChanged(String text) {
    if (text.trim().isEmpty) {
      _yahooApi.cancelPendingSearch();
      _updateState(() {
        _customChartRange = null;
        _mode = _ChartMode.portfolio;
        _searchResults = [];
        _searchLoading = false;
      });
      return;
    }
    _updateState(() {
      _mode = _ChartMode.searching;
      _searchLoading = true;
    });
    runDetachedTask(_runTickerSearch(text), 'Ticker search failed');
  }

  Future<void> _runTickerSearch(String text) async {
    if (!mounted || !widget.isActive) return;
    try {
      final results = await _yahooApi.searchTickers(text);
      if (!mounted || _searchController.text != text) return;
      _updateState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Ticker search failed');
      if (!mounted || _searchController.text != text) return;
      _updateState(() => _searchLoading = false);
    }
  }

  void _moveViStockFocus(int delta) {
    if (_favoriteStocks.isEmpty) return;
    final current = _selectedSymbol == null
        ? -1
        : _favoriteStocks.indexOf(_selectedSymbol!);
    final next = viFocusIndex(current, delta, _favoriteStocks.length);
    if (_favoriteStocks[next] != _selectedSymbol) {
      _selectSymbol(_favoriteStocks[next]);
    }
  }

  void _selectStock(StockResult result) => _selectSymbol(result.symbol);

  void _selectFavorite(String symbol) {
    _updateState(() {
      if (!_selectedFavorites.add(symbol)) {
        _selectedFavorites.remove(symbol);
      }
    });
    if (_selectedFavorites.contains(symbol)) {
      runDetachedTask(
        _syncFavoriteCandle(symbol),
        'Failed to sync selected favorite',
      );
    }
  }

  Color _favoriteColor(String symbol) {
    final index =
        _favoriteStocks.indexOf(symbol).clamp(0, _favoriteStocks.length);
    return chartSeriesColor(
      Theme.of(context).colorScheme,
      context.read<AccountManager>().accounts.length + index,
    );
  }

  void _selectSymbol(String symbol) {
    _searchController.text = symbol;
    _candleSelection.value = null;
    _searchFocus.unfocus();
    _updateState(() {
      _customChartRange = null;
      _pickingChartRange = false;
      _mode = _ChartMode.stock;
      _selectedSymbol = symbol;
      _networkLoading = widget.isActive;
      _stockError = null;
    });
    if (_chartPeriodLoaded) {
      runDetachedTask(_loadSelectedStock(), 'Failed to load selected ticker');
    }
  }

  Future<void> _loadSelectedStock({bool forceRefresh = false}) async {
    if (!mounted || !widget.isActive || _selectedSymbol == null) return;
    final generation = ++_stockLoadGeneration;
    final symbol = _selectedSymbol!;
    final accountManager = context.read<AccountManager>();
    final config = accountManager.ibkrConfigFor();
    final namespace = accountManager.activeAccount;
    final intraday = _usesIntraday;
    final selectedDays = days;
    final contentKey = '$namespace|$symbol|$years|$months|$days';
    final isNewContent = _stockContentKey != contentKey;
    _updateState(() {
      _networkLoading = true;
      _stockError = null;
      if (isNewContent) {
        _intradaySeries = null;
        _stockDailyPreview = const [];
        _stockContentKey = contentKey;
      }
      _nativeCurrency = symbolCurrency(symbol);
      _centDivisor = symbolCentDivisor(symbol);
    });
    // Keep the existing database stream alive during refresh, so cached
    // candles remain on screen while the provider responds.
    if (isNewContent || _stockStream == null) _setStockStream(symbol);

    bool isCurrent() =>
        mounted &&
        widget.isActive &&
        _mode == _ChartMode.stock &&
        _selectedSymbol == symbol &&
        generation == _stockLoadGeneration;
    try {
      if (intraday) {
        if (selectedDays == 5) {
          runDetachedTask(
            _loadFiveDayStockPreview(symbol, generation),
            'Failed to load daily stock preview',
          );
        }
        final series = await _withRemoteLoading(
          () => _intradayData.fetch(
            symbol,
            days: selectedDays,
            config: config,
            forceRefresh: forceRefresh,
          ),
        );
        if (!isCurrent()) return;
        await fetchSymbolCurrencyAndRate(symbol, rawCurrency: series.currency);
        if (!isCurrent()) return;
        requireUsdRate(symbolCurrency(symbol));
        _updateState(() => _intradaySeries = series);
      } else {
        // Even an unresponsive price provider must not leave the chart in a
        // loading state indefinitely. The underlying sync may still update
        // Drift's live candle stream after the visible wait ends.
        await (widget._stockCandleSyncer?.call(
                  symbol,
                  _requiredCandleStart(),
                  forceRefresh,
                ) ??
                syncCandles(
                  symbol,
                  ibkrConfig: config,
                  syncNamespace: namespace,
                  requiredFrom: _requiredCandleStart(),
                  forceRefresh: forceRefresh,
                ))
            .timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            talker.warning('Stock candle refresh still running for $symbol');
          },
        );
        if (!isCurrent()) return;
        await fetchSymbolCurrencyAndRate(symbol).timeout(
          const Duration(seconds: 3),
          onTimeout: () =>
              talker.warning('Stock currency metadata slow for $symbol'),
        );
        if (!isCurrent()) return;
      }
      _updateState(() {
        _nativeCurrency = symbolCurrency(symbol);
        _centDivisor = symbolCentDivisor(symbol);
      });
      _setStockStream(symbol);
    } catch (error, stackTrace) {
      talker.handle(error, stackTrace, 'Selected ticker sync failed');
      if (isCurrent()) _updateState(() => _stockError = error.toString());
    } finally {
      if (isCurrent()) _updateState(() => _networkLoading = false);
    }
  }

  Future<void> _loadFiveDayStockPreview(String symbol, int generation) async {
    final after = DateTime.now().subtract(const Duration(days: 14));
    final rows = await (marketDataDatabase.candles.select()
          ..where(
            (candle) =>
                candle.symbol.equals(canonicalMarketSymbol(symbol)) &
                candle.date.isBiggerThanValue(after),
          )
          ..orderBy([(candle) => OrderingTerm.desc(candle.date)])
          ..limit(5))
        .get();
    if (rows.isEmpty) return;
    // A daily preview must remain available while the live provider is down.
    // Use locally verified metadata and cached FX without waiting for a network
    // refresh, and never show unidentified old units after a transition.
    final metadata = await marketDataDatabase.readSymbolMetadata(symbol);
    final savedRaw = rawCurrencyFromMetadata(metadata);
    if (savedRaw != null) cacheSymbolMeta(symbol, savedRaw);
    if ((await marketDataDatabase.readQuoteCurrencyChanges(symbol))
            .isNotEmpty &&
        rows.any((row) => row.rawCurrency == null)) {
      return;
    }
    final nativeCurrency = symbolCurrency(symbol);
    if (nativeCurrency != 'USD' &&
        !allRatesFromUsd.containsKey(nativeCurrency)) {
      final prefs = await SqliteSettings.getInstance();
      final savedRate = readCachedUsdRate(nativeCurrency, prefs)?.rate;
      if (savedRate != null && savedRate.isFinite && savedRate > 0) {
        allRatesFromUsd[nativeCurrency] = savedRate;
      }
    }
    try {
      requireUsdRate(nativeCurrency);
    } on StateError {
      return;
    }
    if (!mounted ||
        !widget.isActive ||
        !_usesIntraday ||
        days != 5 ||
        _mode != _ChartMode.stock ||
        _selectedSymbol != symbol ||
        generation != _stockLoadGeneration ||
        _intradaySeries != null ||
        rows.isEmpty) {
      return;
    }
    _updateState(() {
      _stockDailyPreview = [
        for (final row in rows.reversed)
          CandleTicker(
            candle: CandlesCompanion(
              date: Value(row.date),
              open: Value(row.open),
              high: Value(row.high),
              low: Value(row.low),
              close: Value(row.close),
              rawCurrency: Value(row.rawCurrency),
            ),
          ),
      ];
    });
  }

  DateTime _requiredCandleStart() {
    final now = DateTime.now();
    return days > 0
        ? DateTime(now.year, now.month, now.day - days - 4)
        : DateTime(now.year - years, now.month - months, now.day - 1);
  }

  void _setStockStream(String symbol) {
    if (!widget.isActive) {
      _stockStream = null;
      return;
    }
    if (_usesIntraday) {
      _stockStream = null;
      _updateState(() {});
      return;
    }
    final after = _requiredCandleStart();
    final marketSymbol = canonicalMarketSymbol(symbol);

    final capturedDays = days;
    _stockStream = (marketDataDatabase.candles.select()
          ..where(
            (candle) =>
                candle.symbol.equals(marketSymbol) &
                candle.date.isBiggerThanValue(after),
          )
          ..orderBy([(candle) => OrderingTerm.asc(candle.date)]))
        .watch()
        .map((rows) {
      final selected = capturedDays > 0 && rows.length > capturedDays
          ? rows.sublist(rows.length - capturedDays)
          : rows;
      return [
        for (final row in selected)
          CandleTicker(
            candle: CandlesCompanion(
              date: Value(row.date),
              open: Value(row.open),
              high: Value(row.high),
              low: Value(row.low),
              close: Value(row.close),
              rawCurrency: Value(row.rawCurrency),
            ),
          ),
      ];
    });
    _updateState(() {});
  }

  (int, int)? _chartRangeFor(List<DateTime> dates) {
    final range = _customChartRange;
    if (range == null || dates.isEmpty) return null;
    final first = dates.indexWhere((date) => !date.isBefore(range.$1));
    final last = dates.lastIndexWhere((date) => !date.isAfter(range.$2));
    final start = first < 0 ? dates.length - 1 : first;
    final end = last < start ? start : last;
    return (start, end);
  }
}
