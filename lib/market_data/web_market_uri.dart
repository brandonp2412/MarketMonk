import 'package:flutter/foundation.dart';

Uri webMarketDataUri(Uri uri) {
  if (!kIsWeb ||
      !{'query1.finance.yahoo.com', 'query2.finance.yahoo.com'}
          .contains(uri.host)) {
    return uri;
  }
  return Uri.base
      .resolve('api/finance${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}');
}
