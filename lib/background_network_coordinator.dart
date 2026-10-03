class BackgroundNetworkCoordinator {
  static const ibkrPortfolioFreshness = Duration(minutes: 5);
  static const ibkrPerformanceFreshness = Duration(minutes: 30);

  final Map<(String, Object), Future<dynamic>> _inFlight = {};
  final Map<(String, Object), Object> _freshnessTokens = {};
  final Map<String, int> _startedByNamespace = {};
  final Map<String, int> _coalescedByNamespace = {};
  final Map<String, int> _freshSkippedByNamespace = {};

  int startedCount(String namespace) => _startedByNamespace[namespace] ?? 0;

  int coalescedCount(String namespace) => _coalescedByNamespace[namespace] ?? 0;

  int freshSkippedCount(String namespace) =>
      _freshSkippedByNamespace[namespace] ?? 0;

  int get activeRequestCount => _inFlight.length;

  void resetDiagnostics() {
    _startedByNamespace.clear();
    _coalescedByNamespace.clear();
    _freshSkippedByNamespace.clear();
  }

  String diagnosticsSummary({String label = 'background requests'}) {
    final namespaces = <String>{
      ..._startedByNamespace.keys,
      ..._coalescedByNamespace.keys,
      ..._freshSkippedByNamespace.keys,
    }.toList()
      ..sort();
    if (namespaces.isEmpty) return '$label: none';

    final details = namespaces.map((namespace) {
      final started = startedCount(namespace);
      final coalesced = coalescedCount(namespace);
      final freshSkipped = freshSkippedCount(namespace);
      return '$namespace started=$started coalesced=$coalesced '
          'fresh-skipped=$freshSkipped';
    }).join('; ');
    return '$label: $details';
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

    _startedByNamespace.update(
      namespace,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    late final Future<T> tracked;
    tracked = Future<T>.sync(request).whenComplete(() {
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
