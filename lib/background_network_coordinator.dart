abstract final class RequestCategory {
  static const ibkrHealth = 'ibkr.health';
  static const ibkrPortfolio = 'ibkr.portfolio';
  static const ibkrPerformance = 'ibkr.performance';
  static const ibkrTrades = 'ibkr.trades';
  static const ibkrHistorical = 'ibkr.historical';
  static const yahooSearch = 'yahoo.search';
  static const yahooSymbolMetadata = 'yahoo.symbolMetadata';
  static const yahooCandles = 'yahoo.candles';
  static const fxRate = 'fx.rate';
  static const marketCandles = 'market.candles';
}

class BackgroundNetworkCoordinator {
  static const ibkrPortfolioFreshness = Duration(minutes: 5);
  static const ibkrPerformanceFreshness = Duration(minutes: 30);

  final Map<(String, Object), Future<dynamic>> _inFlight = {};
  final Map<(String, Object), Object> _freshnessTokens = {};
  final Map<String, int> _startedByNamespace = {};
  final Map<String, int> _completedByNamespace = {};
  final Map<String, int> _failedByNamespace = {};
  final Map<String, int> _coalescedByNamespace = {};
  final Map<String, int> _freshSkippedByNamespace = {};
  final Map<String, int> _rowsByNamespace = {};

  int startedCount(String namespace) => _startedByNamespace[namespace] ?? 0;

  int completedCount(String namespace) => _completedByNamespace[namespace] ?? 0;

  int failedCount(String namespace) => _failedByNamespace[namespace] ?? 0;

  int coalescedCount(String namespace) => _coalescedByNamespace[namespace] ?? 0;

  int freshSkippedCount(String namespace) =>
      _freshSkippedByNamespace[namespace] ?? 0;

  int rowCount(String namespace) => _rowsByNamespace[namespace] ?? 0;

  int get activeRequestCount => _inFlight.length;

  void resetDiagnostics() {
    _startedByNamespace.clear();
    _completedByNamespace.clear();
    _failedByNamespace.clear();
    _coalescedByNamespace.clear();
    _freshSkippedByNamespace.clear();
    _rowsByNamespace.clear();
  }

  void recordRows(String namespace, int rows) {
    if (rows <= 0) return;
    _rowsByNamespace.update(
      namespace,
      (count) => count + rows,
      ifAbsent: () => rows,
    );
  }

  String diagnosticsSummary({String label = 'background requests'}) {
    final namespaces = <String>{
      ..._startedByNamespace.keys,
      ..._completedByNamespace.keys,
      ..._failedByNamespace.keys,
      ..._coalescedByNamespace.keys,
      ..._freshSkippedByNamespace.keys,
      ..._rowsByNamespace.keys,
    }.toList()
      ..sort();
    if (namespaces.isEmpty) return '$label: none';

    final details = namespaces.map((namespace) {
      final started = startedCount(namespace);
      final completed = completedCount(namespace);
      final failed = failedCount(namespace);
      final coalesced = coalescedCount(namespace);
      final freshSkipped = freshSkippedCount(namespace);
      final rows = rowCount(namespace);
      return '$namespace started=$started completed=$completed failed=$failed '
          'coalesced=$coalesced fresh-skipped=$freshSkipped rows=$rows';
    }).join('; ');
    return '$label: $details';
  }

  Future<T> observe<T>(
    String namespace,
    Future<T> Function() request,
  ) async {
    _startedByNamespace.update(
      namespace,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    try {
      final result = await Future<T>.sync(request);
      _completedByNamespace.update(
        namespace,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      return result;
    } catch (_) {
      _failedByNamespace.update(
        namespace,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      rethrow;
    }
  }

  Future<T> coalesce<T>(
    String namespace,
    Object key,
    Future<T> Function() request,
  ) {
    final requestKey = (namespace, key);
    final existing = _inFlight[requestKey];
    if (existing != null) {
      _coalescedByNamespace.update(
        namespace,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      return existing as Future<T>;
    }

    late final Future<T> tracked;
    tracked = observe<T>(namespace, request).whenComplete(() {
      if (identical(_inFlight[requestKey], tracked)) {
        final _ = _inFlight.remove(requestKey);
      }
    });
    _inFlight[requestKey] = tracked;
    return tracked;
  }

  Future<void> runFresh(
    String namespace,
    Object key,
    Object freshnessToken,
    Future<void> Function() request,
  ) {
    final requestKey = (namespace, key);
    if (_freshnessTokens[requestKey] == freshnessToken) {
      _freshSkippedByNamespace.update(
        namespace,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      return Future<void>.value();
    }

    return coalesce<void>(namespace, key, () async {
      if (_freshnessTokens[requestKey] == freshnessToken) {
        _freshSkippedByNamespace.update(
          namespace,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        return;
      }
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
