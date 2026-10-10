import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/logging.dart';

/// Timestamped stock bars kept separate from the daily portfolio cache.
class IntradaySeries {
  /// Raw quote currency, including Yahoo's cent-based codes such as GBp.
  final String currency;

  /// Provider that supplied these bars, which may be Yahoo after IBKR fails.
  final String source;

  /// UTC observations in ascending order, without duplicate timestamps.
  final List<IbkrHistoricalCandle> candles;

  /// Creates an immutable, ordered series and rejects unusable prices.
  IntradaySeries({
    required this.currency,
    required this.source,
    required List<IbkrHistoricalCandle> candles,
  }) : candles = _normalize(candles);

  static List<IbkrHistoricalCandle> _normalize(
    List<IbkrHistoricalCandle> candles,
  ) {
    final byTimestamp = <int, IbkrHistoricalCandle>{};
    for (final candle in candles) {
      if (!candle.date.isUtc ||
          ![candle.open, candle.high, candle.low, candle.close]
              .every((price) => price.isFinite && price > 0)) {
        continue;
      }
      byTimestamp[candle.date.millisecondsSinceEpoch] = candle;
    }
    final sorted = byTimestamp.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.isEmpty) throw StateError('No intraday prices available');
    return List.unmodifiable(sorted);
  }
}

/// Loads short stock ranges from IBKR with Yahoo fallback and a minute cache.
class IntradayMarketData {
  final Future<http.Response> Function(Uri) _yahooGet;
  final Future<IbkrHistoricalSeries> Function(
    IbkrAccountConfig,
    String,
    int,
  ) _ibkrFetch;
  final DateTime Function() _now;
  final _cache = <(String, int, IbkrAccountConfig),
      ({DateTime fetchedAt, IntradaySeries series})>{};

  /// Allows provider requests and time to be substituted for deterministic tests.
  IntradayMarketData({
    Future<http.Response> Function(Uri)? yahooGet,
    Future<IbkrHistoricalSeries> Function(IbkrAccountConfig, String, int)?
        ibkrFetch,
    DateTime Function()? now,
  })  : _yahooGet = yahooGet ?? _getYahoo,
        _ibkrFetch = ibkrFetch ??
            ((config, symbol, days) =>
                IbkrApiClient(config).fetchIntradayCandles(symbol, days: days)),
        _now = now ?? DateTime.now;

  static Future<http.Response> _getYahoo(Uri uri) =>
      http.get(uri, headers: {'User-Agent': 'Mozilla/5.0'});

  /// Uses minute bars for one session and 15-minute bars for five trading days.
  Future<IntradaySeries> fetch(
    String symbol, {
    int days = 1,
    IbkrAccountConfig config = const IbkrAccountConfig(),
    bool forceRefresh = false,
  }) {
    if (days != 1 && days != 5) {
      throw ArgumentError.value(days, 'days', 'Expected 1 or 5');
    }
    final canonicalSymbol = symbol.trim().toUpperCase();
    final key = (canonicalSymbol, days, config);
    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        _now().difference(cached.fetchedAt) < const Duration(minutes: 1)) {
      return Future.value(cached.series);
    }
    return backgroundNetworkCoordinator.coalesce<IntradaySeries>(
      'market.intraday',
      (this, key),
      () async {
        IntradaySeries? series;
        if (config.isConfigured) {
          try {
            final result = await _ibkrFetch(config, canonicalSymbol, days)
                .timeout(const Duration(seconds: 45));
            series = IntradaySeries(
              currency: result.currency,
              source: 'IBKR',
              candles: result.candles,
            );
          } catch (error, stackTrace) {
            talker.handle(
              error,
              stackTrace,
              'IBKR intraday unavailable; trying Yahoo',
            );
          }
        }
        series ??= await _fetchYahoo(canonicalSymbol, days);
        if (_cache.length >= 64) _cache.remove(_cache.keys.first);
        _cache[key] = (fetchedAt: _now(), series: series);
        return series;
      },
    );
  }

  Future<IntradaySeries> _fetchYahoo(String symbol, int days) =>
      backgroundNetworkCoordinator.observe('yahoo.intraday', () async {
        // Yahoo's chart endpoint accepts range and intraday interval parameters.
        // https://github.com/ranaroussi/yfinance/blob/main/yfinance/scrapers/history.py
        final uri = Uri.https(
          'query1.finance.yahoo.com',
          '/v8/finance/chart/$symbol',
          {
            'range': '${days}d',
            'interval': days == 1 ? '1m' : '15m',
            'includePrePost': 'false',
          },
        );
        final response =
            await _yahooGet(uri).timeout(const Duration(seconds: 15));
        if (response.statusCode != 200) {
          throw StateError(
            'Yahoo intraday returned HTTP ${response.statusCode}',
          );
        }
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final chart = body['chart'] as Map<String, dynamic>?;
        if (chart?['error'] != null) {
          throw StateError('Yahoo intraday prices unavailable for $symbol');
        }
        final results = chart?['result'] as List?;
        if (results == null || results.isEmpty) {
          throw StateError('No Yahoo intraday prices available for $symbol');
        }
        final result = results.first as Map<String, dynamic>;
        final meta = result['meta'] as Map<String, dynamic>?;
        final timestamps = result['timestamp'] as List? ?? [];
        final quotes =
            (result['indicators'] as Map<String, dynamic>?)?['quote'] as List?;
        if (quotes == null || quotes.isEmpty) {
          throw StateError('No Yahoo intraday prices available for $symbol');
        }
        final quote = quotes.first as Map<String, dynamic>;
        num? numberAt(String field, int index) {
          final values = quote[field] as List?;
          final value =
              values != null && index < values.length ? values[index] : null;
          return value is num && value.isFinite ? value : null;
        }

        final candles = <IbkrHistoricalCandle>[];
        for (var i = 0; i < timestamps.length; i++) {
          final timestamp = timestamps[i];
          final open = numberAt('open', i);
          final high = numberAt('high', i);
          final low = numberAt('low', i);
          final close = numberAt('close', i);
          if (timestamp is! num ||
              !timestamp.isFinite ||
              timestamp <= 0 ||
              open == null ||
              high == null ||
              low == null ||
              close == null) {
            continue;
          }
          final volume = numberAt('volume', i)?.toInt() ?? 0;
          candles.add(
            IbkrHistoricalCandle(
              date: DateTime.fromMillisecondsSinceEpoch(
                (timestamp * 1000).round(),
                isUtc: true,
              ),
              open: open.toDouble(),
              high: high.toDouble(),
              low: low.toDouble(),
              close: close.toDouble(),
              volume: volume < 0 ? 0 : volume,
            ),
          );
        }
        return IntradaySeries(
          currency: meta?['currency'] as String? ?? 'USD',
          source: 'Yahoo',
          candles: candles,
        );
      });
}
