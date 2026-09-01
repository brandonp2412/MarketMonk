import 'dart:convert';

import 'package:http/http.dart' as http;

/// Per-MarketMonk-account connection details for a self-hosted IBKR service.
class IbkrAccountConfig {
  final bool enabled;
  final String baseUrl;
  final String token;

  const IbkrAccountConfig({
    this.enabled = false,
    this.baseUrl = '',
    this.token = '',
  });

  bool get isConfigured =>
      enabled && baseUrl.trim().isNotEmpty && token.trim().isNotEmpty;

  IbkrAccountConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? token,
  }) =>
      IbkrAccountConfig(
        enabled: enabled ?? this.enabled,
        baseUrl: baseUrl ?? this.baseUrl,
        token: token ?? this.token,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'baseUrl': baseUrl,
        'token': token,
      };

  @override
  bool operator ==(Object other) =>
      other is IbkrAccountConfig &&
      enabled == other.enabled &&
      baseUrl == other.baseUrl &&
      token == other.token;

  @override
  int get hashCode => Object.hash(enabled, baseUrl, token);

  factory IbkrAccountConfig.fromJson(Map<String, dynamic> json) =>
      IbkrAccountConfig(
        enabled: json['enabled'] == true,
        baseUrl: json['baseUrl'] as String? ?? '',
        token: json['token'] as String? ?? '',
      );
}

/// One current position returned by the self-hosted IBKR service.
class IbkrPosition {
  final String symbol;
  final String securityType;
  final String currency;
  final String exchange;
  final int conid;
  final double quantity;
  final double? marketPrice;
  final double? marketValue;
  final double? averageCost;
  final double? unrealizedPnl;
  final double? realizedPnl;

  const IbkrPosition({
    required this.symbol,
    required this.securityType,
    required this.currency,
    required this.exchange,
    required this.conid,
    required this.quantity,
    required this.marketPrice,
    required this.marketValue,
    required this.averageCost,
    required this.unrealizedPnl,
    required this.realizedPnl,
  });

  factory IbkrPosition.fromJson(Map<String, dynamic> json) => IbkrPosition(
        symbol: json['symbol'] as String? ?? '',
        securityType: json['security_type'] as String? ?? '',
        currency: json['currency'] as String? ?? 'USD',
        exchange: json['exchange'] as String? ?? '',
        conid: (json['conid'] as num?)?.toInt() ?? 0,
        quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
        marketPrice: (json['market_price'] as num?)?.toDouble(),
        marketValue: (json['market_value'] as num?)?.toDouble(),
        averageCost: (json['average_cost'] as num?)?.toDouble(),
        unrealizedPnl: (json['unrealized_pnl'] as num?)?.toDouble(),
        realizedPnl: (json['realized_pnl'] as num?)?.toDouble(),
      );
}

/// One daily historical candle returned by the self-hosted IBKR service.
class IbkrHistoricalCandle {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  const IbkrHistoricalCandle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  factory IbkrHistoricalCandle.fromJson(Map<String, dynamic> json) =>
      IbkrHistoricalCandle(
        date: DateTime.parse(json['date'] as String),
        open: (json['open'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        close: (json['close'] as num).toDouble(),
        volume: (json['volume'] as num?)?.toInt() ?? 0,
      );
}

/// Historical daily bars and quote currency for one IBKR stock position.
class IbkrHistoricalSeries {
  final String symbol;
  final String currency;
  final List<IbkrHistoricalCandle> candles;

  const IbkrHistoricalSeries({
    required this.symbol,
    required this.currency,
    required this.candles,
  });

  factory IbkrHistoricalSeries.fromJson(Map<String, dynamic> json) =>
      IbkrHistoricalSeries(
        symbol: json['symbol'] as String? ?? '',
        currency: json['currency'] as String? ?? 'USD',
        candles: (json['candles'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(IbkrHistoricalCandle.fromJson)
            .toList(),
      );
}

/// One monetary account value reported by IBKR.
class IbkrAccountValue {
  final double value;
  final String currency;

  const IbkrAccountValue({required this.value, required this.currency});

  @override
  bool operator ==(Object other) =>
      other is IbkrAccountValue &&
      value == other.value &&
      currency == other.currency;

  @override
  int get hashCode => Object.hash(value, currency);
}

/// Current read-only snapshot returned by the MarketMonk IBKR API.
class IbkrPortfolioSnapshot {
  final String account;
  final List<IbkrPosition> positions;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> ledger;

  const IbkrPortfolioSnapshot({
    required this.account,
    required this.positions,
    required this.summary,
    required this.ledger,
  });

  /// Returns an account-summary monetary value by its IBKR tag.
  IbkrAccountValue? summaryValue(String tag) {
    final raw = summary[tag.toLowerCase()] ?? summary[tag];
    if (raw is! Map<String, dynamic>) return null;
    final amount = raw['value'] ?? raw['amount'];
    if (amount is! num) return null;
    return IbkrAccountValue(
      value: amount.toDouble(),
      currency: raw['currency'] as String? ?? '',
    );
  }

  /// Account net liquidation in the broker-reported base currency.
  IbkrAccountValue? get netLiquidation => summaryValue('netliquidation');

  /// Account net liquidation expressed in USD when the broker reports it.
  IbkrAccountValue? get netLiquidationUsd {
    final explicitUsd = summaryValue('netliquidationbycurrency:usd');
    if (explicitUsd?.currency == 'USD') return explicitUsd;
    final byCurrency = summaryValue('netliquidationbycurrency');
    if (byCurrency?.currency == 'USD') return byCurrency;
    final total = netLiquidation;
    return total?.currency == 'USD' ? total : null;
  }

  factory IbkrPortfolioSnapshot.fromJson(Map<String, dynamic> json) {
    final positions = (json['positions'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(IbkrPosition.fromJson)
        .where((position) => position.symbol.isNotEmpty)
        .toList();
    return IbkrPortfolioSnapshot(
      account: json['account'] as String? ?? '',
      positions: positions,
      summary: (json['summary'] as Map<String, dynamic>?) ?? const {},
      ledger: (json['ledger'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// Client for the small read-only service hosted alongside the IBKR gateway.
class IbkrApiClient {
  final IbkrAccountConfig config;
  final Future<http.Response> Function(Uri, {Map<String, String>? headers})
      _get;

  IbkrApiClient(
    this.config, {
    Future<http.Response> Function(Uri, {Map<String, String>? headers})? get,
  }) : _get = get ?? http.get;

  Future<void> testConnection() async {
    final response = await _request('/v1/health');
    final body = json.decode(response.body) as Map<String, dynamic>;
    if (body['status'] != 'ok') {
      throw StateError(
        body['detail'] ?? body['error'] ?? 'IBKR API unavailable',
      );
    }
  }

  Future<IbkrPortfolioSnapshot> fetchPortfolio() async {
    final response = await _request('/v1/portfolio');
    return IbkrPortfolioSnapshot.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  /// Fetches up to [years] years of daily bars for a current IBKR stock position.
  Future<IbkrHistoricalSeries> fetchHistoricalCandles(
    String symbol, {
    int years = 10,
  }) async {
    if (years < 1 || years > 10) {
      throw RangeError.range(years, 1, 10, 'years');
    }
    final response = await _request(
      '/v1/historical',
      queryParameters: {'symbol': symbol, 'years': '$years'},
    );
    return IbkrHistoricalSeries.fromJson(
      json.decode(response.body) as Map<String, dynamic>,
    );
  }

  Future<http.Response> _request(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    if (!config.isConfigured) {
      throw StateError('IBKR API is not fully configured');
    }
    final base = Uri.parse(config.baseUrl.trim());
    if (!base.hasScheme || base.host.isEmpty) {
      throw FormatException('IBKR API URL must include http:// or https://');
    }
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/$'), '')}$path',
      queryParameters: queryParameters,
      fragment: null,
    );
    final response = await _get(
      uri,
      headers: {'Authorization': 'Bearer ${config.token.trim()}'},
    );
    if (response.statusCode != 200) {
      String detail = 'HTTP ${response.statusCode}';
      try {
        final body = json.decode(response.body) as Map<String, dynamic>;
        detail =
            body['detail'] as String? ?? body['error'] as String? ?? detail;
      } catch (_) {}
      throw StateError(detail);
    }
    return response;
  }
}
