import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/background_network_coordinator.dart';

void main() {
  test('duplicate callers share one in-flight request', () async {
    final coordinator = BackgroundNetworkCoordinator();
    final gate = Completer<int>();
    var calls = 0;

    Future<int> load() {
      calls++;
      return gate.future;
    }

    final first = coordinator.coalesce<int>('resource', 'same-key', load);
    final second = coordinator.coalesce<int>('resource', 'same-key', load);

    expect(calls, 1);
    gate.complete(42);
    expect(await Future.wait([first, second]), [42, 42]);
  });

  test('failed request is removed so a later caller can retry', () async {
    final coordinator = BackgroundNetworkCoordinator();
    var calls = 0;

    Future<int> load() async {
      calls++;
      if (calls == 1) throw StateError('temporary failure');
      return 7;
    }

    await expectLater(
      coordinator.coalesce<int>('resource', 'same-key', load),
      throwsStateError,
    );

    expect(await coordinator.coalesce<int>('resource', 'same-key', load), 7);
    expect(calls, 2);
  });

  test('freshness is recorded only after successful completion', () async {
    final coordinator = BackgroundNetworkCoordinator();
    var calls = 0;

    Future<void> load() async {
      calls++;
      if (calls == 1) throw StateError('temporary failure');
    }

    await expectLater(
      coordinator.runFresh('history', 'AAPL', '2026-10-03', load),
      throwsStateError,
    );
    await coordinator.runFresh('history', 'AAPL', '2026-10-03', load);
    await coordinator.runFresh('history', 'AAPL', '2026-10-03', load);

    expect(calls, 2);
  });
}
