import 'package:flutter/foundation.dart';

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
