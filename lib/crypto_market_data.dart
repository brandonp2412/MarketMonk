import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:market_monk/ibkr_api.dart';

class CryptoAsset {
  const CryptoAsset(this.symbol, this.name, this.llamaId, this.krakenPair);

  final String symbol;
  final String name;
  final String llamaId;
  final String krakenPair;
}

const cryptoAssets = <CryptoAsset>[
  CryptoAsset('BTC-USD', 'Bitcoin', 'bitcoin', 'XBTUSD'),
  CryptoAsset('ETH-USD', 'Ethereum', 'ethereum', 'ETHUSD'),
  CryptoAsset('XMR-USD', 'Monero', 'monero', 'XMRUSD'),
  CryptoAsset('SOL-USD', 'Solana', 'solana', 'SOLUSD'),
  CryptoAsset('XRP-USD', 'XRP', 'ripple', 'XRPUSD'),
  CryptoAsset('ADA-USD', 'Cardano', 'cardano', 'ADAUSD'),
  CryptoAsset('DOGE-USD', 'Dogecoin', 'dogecoin', 'XDGUSD'),
  CryptoAsset('LTC-USD', 'Litecoin', 'litecoin', 'LTCUSD'),
  CryptoAsset('BCH-USD', 'Bitcoin Cash', 'bitcoin-cash', 'BCHUSD'),
  CryptoAsset('DOT-USD', 'Polkadot', 'polkadot', 'DOTUSD'),
  CryptoAsset('LINK-USD', 'Chainlink', 'chainlink', 'LINKUSD'),
  CryptoAsset('AVAX-USD', 'Avalanche', 'avalanche-2', 'AVAXUSD'),
];

CryptoAsset? cryptoAssetForSymbol(String symbol) {
  final normalized = symbol.trim().toUpperCase();
  for (final asset in cryptoAssets) {
    if (asset.symbol == normalized) return asset;
  }
  return null;
}

List<CryptoAsset> searchCryptoAssets(String query) {
  final normalized = query.trim().toUpperCase();
  if (normalized.isEmpty) return const [];
  return cryptoAssets
      .where(
        (asset) =>
            asset.symbol.contains(normalized) ||
            asset.symbol.split('-').first == normalized ||
            asset.name.toUpperCase().contains(normalized),
      )
      .toList(growable: false);
}

class CryptoDailyBar {
  const CryptoDailyBar({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
  });

  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
}

class CryptoPriceQuote {
  const CryptoPriceQuote(this.priceUsd, this.source, this.timestamp);

  final double priceUsd;
  final String source;
  final DateTime timestamp;
}

class CryptoMarketData {
  CryptoMarketData({Future<http.Response> Function(Uri)? fetch})
      : _fetch = fetch ??
            ((uri) => http.get(uri, headers: {'User-Agent': 'Mozilla/5.0'}));

  final Future<http.Response> Function(Uri) _fetch;

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _fetch(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError(
        'Crypto price source returned HTTP ${response.statusCode}',
      );
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid crypto price response');
    }
    return value;
  }

  static double _price(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (value == null || !value.isFinite || value <= 0) {
      throw const FormatException('Invalid crypto price');
    }
    return value;
  }

  Future<CryptoPriceQuote> currentPrice(CryptoAsset asset) async {
    try {
      final key = 'coingecko:${asset.llamaId}';
      final json = await _getJson(
        Uri.https('coins.llama.fi', '/prices/current/$key'),
      );
      final coins = json['coins'] as Map<String, dynamic>;
      final quote = coins[key] as Map<String, dynamic>;
      final timestamp = (quote['timestamp'] as num).toInt();
      final observedAt = DateTime.fromMillisecondsSinceEpoch(
        timestamp * 1000,
        isUtc: true,
      );
      if (DateTime.now().toUtc().difference(observedAt).abs() >
          const Duration(minutes: 30)) {
        throw StateError('Crypto quote is stale');
      }
      return CryptoPriceQuote(_price(quote['price']), 'DefiLlama', observedAt);
    } catch (_) {
      final result = await _krakenResult(asset.krakenPair, '/0/public/Ticker');
      final data = result.first.value as Map<String, dynamic>;
      final last = data['c'] as List<dynamic>;
      return CryptoPriceQuote(
        _price(last.first),
        'Kraken',
        DateTime.now().toUtc(),
      );
    }
  }

  Future<List<CryptoDailyBar>> dailyHistory(
    CryptoAsset asset,
    DateTime from,
  ) async {
    if (DateTime.now().toUtc().difference(from.toUtc()).inDays <= 700) {
      try {
        final candles = await _krakenDailyHistory(asset, from);
        if (candles.isNotEmpty &&
            !candles.first.date.isAfter(from.add(const Duration(days: 1)))) {
          return candles;
        }
      } catch (_) {}
    }
    try {
      final candles = await _yahooDailyHistory(asset, from);
      if (candles.isNotEmpty) return candles;
    } catch (_) {}
    try {
      final prices = await _llamaHistory(asset, from);
      if (prices.isNotEmpty) return prices;
    } catch (_) {}
    return _krakenDailyHistory(asset, from);
  }

  Future<List<CryptoDailyBar>> _yahooDailyHistory(
    CryptoAsset asset,
    DateTime from,
  ) async {
    final fromUtc = DateTime.utc(from.year, from.month, from.day);
    final through = DateTime.now().toUtc().add(const Duration(days: 1));
    final json = await _getJson(
      Uri.https(
        'query1.finance.yahoo.com',
        '/v8/finance/chart/${asset.symbol}',
        {
          'period1': '${fromUtc.millisecondsSinceEpoch ~/ 1000}',
          'period2': '${through.millisecondsSinceEpoch ~/ 1000}',
          'interval': '1d',
        },
      ),
    );
    final chart = json['chart'] as Map<String, dynamic>;
    final result =
        (chart['result'] as List<dynamic>).first as Map<String, dynamic>;
    final timestamps = result['timestamp'] as List<dynamic>;
    final indicators = result['indicators'] as Map<String, dynamic>;
    final quote =
        (indicators['quote'] as List<dynamic>).first as Map<String, dynamic>;
    final opens = quote['open'] as List<dynamic>;
    final highs = quote['high'] as List<dynamic>;
    final lows = quote['low'] as List<dynamic>;
    final closes = quote['close'] as List<dynamic>;
    final volumes = quote['volume'] as List<dynamic>?;
    final bars = <CryptoDailyBar>[];
    for (var i = 0; i < timestamps.length; i++) {
      try {
        final utc = DateTime.fromMillisecondsSinceEpoch(
          (timestamps[i] as num).toInt() * 1000,
          isUtc: true,
        );
        final open = _price(opens[i]);
        final high = _price(highs[i]);
        final low = _price(lows[i]);
        final close = _price(closes[i]);
        if (high < open || high < close || low > open || low > close) {
          continue;
        }
        bars.add(
          CryptoDailyBar(
            date: DateTime(utc.year, utc.month, utc.day),
            open: open,
            high: high,
            low: low,
            close: close,
            volume: volumes == null || volumes[i] == null
                ? 0
                : (volumes[i] as num).toDouble(),
          ),
        );
      } catch (_) {}
    }
    return bars;
  }

  Future<List<CryptoDailyBar>> _llamaHistory(
    CryptoAsset asset,
    DateTime from,
  ) async {
    final fromUtc = DateTime.utc(from.year, from.month, from.day);
    final totalSpan = DateTime.now().toUtc().difference(fromUtc).inDays + 2;
    final key = 'coingecko:${asset.llamaId}';
    final byDate = <int, CryptoDailyBar>{};
    for (var offset = 0; offset < totalSpan; offset += 500) {
      final chunkStart = fromUtc.add(Duration(days: offset));
      final span = (totalSpan - offset).clamp(1, 500);
      Map<String, dynamic> json;
      try {
        json = await _getJson(
          Uri.https('coins.llama.fi', '/chart/$key', {
            'start': '${chunkStart.millisecondsSinceEpoch ~/ 1000}',
            'span': '$span',
            'period': '1d',
          }),
        );
      } catch (_) {
        if (byDate.isEmpty) rethrow;
        break;
      }
      final coin =
          (json['coins'] as Map<String, dynamic>)[key] as Map<String, dynamic>;
      final values = coin['prices'] as List<dynamic>;
      for (final item in values) {
        try {
          final point = item as Map<String, dynamic>;
          final timestamp = (point['timestamp'] as num).toInt();
          final utc = DateTime.fromMillisecondsSinceEpoch(
            timestamp * 1000,
            isUtc: true,
          );
          final rounded = utc.add(const Duration(hours: 12));
          final date = DateTime(rounded.year, rounded.month, rounded.day);
          if (date.isBefore(DateTime(from.year, from.month, from.day)))
            continue;
          final price = _price(point['price']);
          byDate[date.millisecondsSinceEpoch] = CryptoDailyBar(
            date: date,
            open: price,
            high: price,
            low: price,
            close: price,
          );
        } catch (_) {}
      }
    }
    try {
      final quote = await currentPrice(asset);
      final utc = quote.timestamp.toUtc();
      final today = DateTime(utc.year, utc.month, utc.day);
      byDate[today.millisecondsSinceEpoch] = CryptoDailyBar(
        date: today,
        open: quote.priceUsd,
        high: quote.priceUsd,
        low: quote.priceUsd,
        close: quote.priceUsd,
      );
    } catch (_) {}
    final bars = byDate.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return bars;
  }

  Future<List<CryptoDailyBar>> _krakenDailyHistory(
    CryptoAsset asset,
    DateTime from,
  ) async {
    final values = await _krakenCandles(asset.krakenPair, 1440);
    final start = DateTime(from.year, from.month, from.day);
    return values
        .map((value) {
          final utc = DateTime.fromMillisecondsSinceEpoch(
            (value[0] as num).toInt() * 1000,
            isUtc: true,
          );
          return CryptoDailyBar(
            date: DateTime(utc.year, utc.month, utc.day),
            open: _price(value[1]),
            high: _price(value[2]),
            low: _price(value[3]),
            close: _price(value[4]),
            volume: double.tryParse('${value[6]}') ?? 0,
          );
        })
        .where((bar) => !bar.date.isBefore(start))
        .toList();
  }

  Future<List<IbkrHistoricalCandle>> intradayHistory(
    CryptoAsset asset, {
    required int days,
  }) async {
    final interval = days == 1 ? 5 : 15;
    final values = await _krakenCandles(asset.krakenPair, interval);
    final start = DateTime.now().toUtc().subtract(Duration(days: days));
    final bars = <IbkrHistoricalCandle>[];
    for (final value in values) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        (value[0] as num).toInt() * 1000,
        isUtc: true,
      );
      if (date.isBefore(start)) continue;
      bars.add(
        IbkrHistoricalCandle(
          date: date,
          open: _price(value[1]),
          high: _price(value[2]),
          low: _price(value[3]),
          close: _price(value[4]),
          volume: (double.tryParse('${value[6]}') ?? 0).round(),
        ),
      );
    }
    if (bars.isEmpty) throw StateError('No crypto intraday prices available');
    return bars;
  }

  Future<List<dynamic>> _krakenCandles(String pair, int interval) async {
    final result = await _krakenResult(pair, '/0/public/OHLC', {
      'interval': '$interval',
    });
    return result.first.value as List<dynamic>;
  }

  Future<Iterable<MapEntry<String, dynamic>>> _krakenResult(
    String pair,
    String path, [
    Map<String, String> parameters = const {},
  ]) async {
    final json = await _getJson(
      Uri.https('api.kraken.com', path, {'pair': pair, ...parameters}),
    );
    final errors = json['error'] as List<dynamic>? ?? const [];
    if (errors.isNotEmpty) throw StateError('Kraken market data unavailable');
    final result = json['result'] as Map<String, dynamic>;
    final entries = result.entries.where((entry) => entry.key != 'last');
    if (entries.isEmpty) throw StateError('Crypto market not found: $pair');
    return entries;
  }
}
