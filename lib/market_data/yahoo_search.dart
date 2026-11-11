import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/crypto_market_data.dart';
import 'package:market_monk/logging.dart';

class YahooFinanceApi {
  static const String _baseUrl =
      'https://query1.finance.yahoo.com/v1/finance/search';

  final Future<http.Response> Function(Uri) _searchFetcher;
  Timer? _debounceTimer;
  Completer<List<StockResult>>? _pendingSearch;
  String? _pendingQuery;

  YahooFinanceApi({Future<http.Response> Function(Uri)? searchFetcher})
      : _searchFetcher = searchFetcher ?? http.get;

  Future<List<StockResult>> searchTickers(String query) {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      cancelPendingSearch();
      return Future.value([]);
    }

    final pending = _pendingSearch;
    if (_pendingQuery == trimmedQuery && pending != null) {
      return pending.future;
    }

    cancelPendingSearch();
    final completer = Completer<List<StockResult>>();
    _pendingSearch = completer;
    _pendingQuery = trimmedQuery;

    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final result = await _performSearch(trimmedQuery);
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        talker.handle(error, stackTrace, 'Ticker search request failed');
        if (!completer.isCompleted) completer.complete([]);
      } finally {
        if (identical(_pendingSearch, completer)) {
          _pendingSearch = null;
          _pendingQuery = null;
          _debounceTimer = null;
        }
      }
    });

    return completer.future;
  }

  Future<List<StockResult>> _performSearch(String query) =>
      backgroundNetworkCoordinator.coalesce<List<StockResult>>(
        'yahoo.search',
        query,
        () async {
          final crypto = searchCryptoAssets(query)
              .map(
                (asset) => StockResult(
                  symbol: asset.symbol,
                  shortname: asset.name,
                  longname: asset.name,
                  exchange: 'Crypto',
                ),
              )
              .toList();
          try {
            final response = await _searchFetcher(
              Uri.parse('$_baseUrl?q=${Uri.encodeComponent(query)}'),
            ).timeout(const Duration(seconds: 5));

            if (response.statusCode != 200) {
              talker.warning(
                'Ticker search returned HTTP ${response.statusCode}',
              );
              return crypto;
            }

            final Map<String, dynamic> data = json.decode(response.body);
            final List<dynamic> quotes = data['quotes'] ?? [];

            // Include EQUITYs, ETFs, and ETNs — all have tradeable candle data.
            const tradeable = {'EQUITY', 'ETF', 'ETN'};
            final stocks = quotes
                .where((quote) => tradeable.contains(quote['quoteType']))
                .map((quote) => StockResult.fromJson(quote))
                .where(
                  (stock) => !crypto.any((coin) => coin.symbol == stock.symbol),
                );
            return [...crypto, ...stocks];
          } catch (error, stackTrace) {
            talker.handle(error, stackTrace, 'Ticker search request failed');
            return crypto;
          }
        },
      );

  void cancelPendingSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final pending = _pendingSearch;
    _pendingSearch = null;
    _pendingQuery = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete([]);
    }
  }

  void dispose() => cancelPendingSearch();
}

class StockResult {
  final String symbol;
  final String shortname;
  final String longname;
  final String exchange;

  StockResult({
    required this.symbol,
    required this.shortname,
    required this.longname,
    required this.exchange,
  });

  factory StockResult.fromJson(Map<String, dynamic> json) {
    return StockResult(
      symbol: json['symbol'] ?? '',
      shortname: json['shortname'] ?? '',
      longname: json['longname'] ?? '',
      exchange: json['exchange'] ?? '',
    );
  }

  @override
  String toString() =>
      '$symbol ($exchange) - ${longname.isNotEmpty ? longname : shortname}';
}
