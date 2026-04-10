import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Client for the Interactive Brokers Client Portal Web API.
///
/// Requires IB Gateway or Trader Workstation running locally (or on the LAN)
/// with the Client Portal API enabled. The gateway uses a self-signed TLS
/// certificate, so certificate validation is intentionally bypassed for this
/// connection only.
///
/// See: https://interactivebrokers.github.io/cpwebapi/
class IbApi {
  final String host;
  final int port;
  late final http.Client _client;

  IbApi({this.host = 'localhost', this.port = 5000}) {
    // Bypass self-signed cert on the local IB Gateway only.
    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, h, p) => true;
    _client = IOClient(ioClient);
  }

  String get _base => 'https://$host:$port/v1/api';

  Future<Map<String, dynamic>> _get(String path) async {
    final resp = await _client.get(Uri.parse('$_base/$path'));
    if (resp.statusCode != 200) {
      throw Exception('IB API $path → ${resp.statusCode}: ${resp.body}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> _getList(String path) async {
    final resp = await _client.get(Uri.parse('$_base/$path'));
    if (resp.statusCode != 200) {
      throw Exception('IB API $path → ${resp.statusCode}: ${resp.body}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is List) return decoded;
    // Some endpoints wrap the list under a key
    if (decoded is Map && decoded.containsKey('orders')) {
      return decoded['orders'] as List;
    }
    return [];
  }

  Future<Map<String, dynamic>> _post(String path) async {
    final resp = await _client.post(Uri.parse('$_base/$path'));
    if (resp.statusCode != 200) {
      throw Exception('IB API $path → ${resp.statusCode}: ${resp.body}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// Returns true if the gateway session is authenticated.
  Future<bool> checkAuth() async {
    try {
      final data = await _get('iserver/auth/status');
      return data['authenticated'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers a session reauthentication (call if [checkAuth] returns false).
  Future<void> reauthenticate() => _post('iserver/reauthenticate');

  /// Returns the list of IB account IDs available in the session.
  Future<List<String>> getAccounts() async {
    final data = await _getList('portfolio/accounts');
    return data
        .map((a) => (a as Map<String, dynamic>)['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  /// Returns open positions for [accountId].
  Future<List<IbPosition>> getPositions(String accountId) async {
    final data = await _getList('portfolio/$accountId/positions/0');
    return data
        .map((p) => IbPosition.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Returns recent executions (filled orders).
  Future<List<IbTrade>> getTrades() async {
    final data = await _getList('iserver/account/trades');
    return data
        .map((t) => IbTrade.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// Searches for a contract and returns its conid, or null if not found.
  Future<int?> findConid(String symbol) async {
    final resp = await _client.get(
      Uri.parse(
        '$_base/iserver/secdef/search?symbol=${Uri.encodeComponent(symbol)}&secType=STK',
      ),
    );
    if (resp.statusCode != 200) return null;
    final data = json.decode(resp.body) as List<dynamic>;
    if (data.isEmpty) return null;
    return (data.first as Map<String, dynamic>)['conid'] as int?;
  }

  /// Returns historical price bars for [conid].
  ///
  /// [period] examples: '1d', '1w', '1m', '3m', '6m', '1y'
  /// [bar] examples: '5min', '15min', '1h', '1d'
  Future<List<IbCandle>> getHistoricalData({
    required int conid,
    required String period,
    required String bar,
  }) async {
    final resp = await _client.get(
      Uri.parse(
        '$_base/iserver/marketdata/history'
        '?conid=$conid&period=$period&bar=$bar&outsideRth=false',
      ),
    );
    if (resp.statusCode != 200) {
      throw Exception(
        'IB historical data → ${resp.statusCode}: ${resp.body}',
      );
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final bars = data['data'] as List<dynamic>? ?? [];
    return bars
        .map((b) => IbCandle.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  void dispose() => _client.close();
}

class IbPosition {
  final String symbol;
  final double shares;
  final double avgCost;
  final double marketPrice;
  final String conid;

  const IbPosition({
    required this.symbol,
    required this.shares,
    required this.avgCost,
    required this.marketPrice,
    required this.conid,
  });

  factory IbPosition.fromJson(Map<String, dynamic> json) {
    return IbPosition(
      symbol: json['ticker'] as String? ?? json['symbol'] as String? ?? '',
      shares: (json['position'] as num?)?.toDouble() ?? 0,
      avgCost: (json['avgCost'] as num?)?.toDouble() ?? 0,
      marketPrice: (json['mktPrice'] as num?)?.toDouble() ?? 0,
      conid: json['conid']?.toString() ?? '',
    );
  }
}

class IbTrade {
  final String symbol;
  final double size;
  final double price;

  /// 'B' = buy, 'S' = sell.
  final String side;
  final DateTime tradeTime;

  const IbTrade({
    required this.symbol,
    required this.size,
    required this.price,
    required this.side,
    required this.tradeTime,
  });

  factory IbTrade.fromJson(Map<String, dynamic> json) {
    final tsMs = json['trade_time_r'] as int?;
    return IbTrade(
      symbol: json['symbol'] as String? ?? '',
      size: (json['size'] as num?)?.toDouble() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      side: json['side'] as String? ?? 'B',
      tradeTime: tsMs != null
          ? DateTime.fromMillisecondsSinceEpoch(tsMs)
          : DateTime.now(),
    );
  }
}

class IbCandle {
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  const IbCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory IbCandle.fromJson(Map<String, dynamic> json) {
    // IB returns bar timestamps as milliseconds in the 't' field.
    final t = json['t'] as int? ?? 0;
    return IbCandle(
      time: DateTime.fromMillisecondsSinceEpoch(t),
      open: (json['o'] as num?)?.toDouble() ?? 0,
      high: (json['h'] as num?)?.toDouble() ?? 0,
      low: (json['l'] as num?)?.toDouble() ?? 0,
      close: (json['c'] as num?)?.toDouble() ?? 0,
      volume: (json['v'] as num?)?.toInt() ?? 0,
    );
  }
}
