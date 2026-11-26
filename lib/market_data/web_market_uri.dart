import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:market_monk/market_data/web_rate_limit_notice.dart';

const _financeBaseUrl = String.fromEnvironment('MARKET_MONK_FINANCE_BASE_URL');

Uri resolveWebMarketDataUri(Uri uri, Uri pageUri, String financeBaseUrl) {
  if (!{
    'query1.finance.yahoo.com',
    'query2.finance.yahoo.com',
  }.contains(uri.host)) {
    return uri;
  }
  final path = 'api/finance${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
  if (financeBaseUrl.isEmpty) return pageUri.resolve(path);
  final base = Uri.parse(financeBaseUrl);
  if (base.scheme != 'https' ||
      !base.hasAuthority ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    throw StateError('Market data gateway must be an HTTPS base URL');
  }
  return base
      .replace(path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/')
      .resolve(path);
}

Uri webMarketDataUri(Uri uri) =>
    kIsWeb ? resolveWebMarketDataUri(uri, Uri.base, _financeBaseUrl) : uri;

/// Centralized Yahoo transport so every public web-data consumer sees limits.
Future<http.Response> marketDataGet(
  Uri uri, {
  Map<String, String>? headers,
}) async {
  final target = webMarketDataUri(uri);
  final hostedGateway = kIsWeb && _financeBaseUrl.isNotEmpty && target != uri;
  try {
    final response = await http.get(target, headers: headers);
    if (hostedGateway) {
      final problem = classifyWebMarketResponse(response);
      if (problem != null) webRateLimitNotice.report(problem);
    }
    return response;
  } on http.ClientException {
    // Cloudflare may reject quota-exhausted requests before executing the
    // Worker, without CORS headers. The browser then conceals the HTTP status.
    if (hostedGateway) {
      webRateLimitNotice.report(WebMarketProblem.unavailable);
    }
    rethrow;
  }
}
