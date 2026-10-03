class BackgroundNetworkCoordinator {
  static const ibkrPortfolioFreshness = Duration(minutes: 5);
  static const ibkrPerformanceFreshness = Duration(minutes: 30);

  final Map<(String, Object), Future<dynamic>> _inFlight = {};
  final Map<(String, Object), Object> _freshnessTokens = {};

  Future<T> coalesce<T>(
    String namespace,
    Object key,
    Future<T> Function() request,
  ) {
    final requestKey = (namespace, key);
    final existing = _inFlight[requestKey];
    if (existing != null) {
      return existing as Future<T>;
    }

    final future = Future<T>.sync(request);
    _inFlight[requestKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[requestKey], future)) {
        _inFlight.remove(requestKey);
      }
    });
  }

  Future<void> runFresh(
    String namespace,
    Object key,
    Object freshnessToken,
    Future<void> Function() request,
  ) {
    final requestKey = (namespace, key);
    if (_freshnessTokens[requestKey] == freshnessToken) {
      return Future<void>.value();
    }

    return coalesce<void>(namespace, key, () async {
      if (_freshnessTokens[requestKey] == freshnessToken) return;
      await request();
      _freshnessTokens[requestKey] = freshnessToken;
    });
  }

  bool isTimestampFresh(DateTime cachedAt, Duration maxAge, {DateTime? now}) =>
      (now ?? DateTime.now()).difference(cachedAt) <= maxAge;

  void clearFreshness(String namespace, {bool Function(Object key)? where}) {
    _freshnessTokens.removeWhere(
      (entry, _) => entry.$1 == namespace && (where == null || where(entry.$2)),
    );
  }
}

final backgroundNetworkCoordinator = BackgroundNetworkCoordinator();
