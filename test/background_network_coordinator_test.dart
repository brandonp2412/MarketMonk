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

  test('diagnostics expose request counts without request keys', () async {
    final coordinator = BackgroundNetworkCoordinator();
    final gate = Completer<int>();

    final first = coordinator.coalesce<int>(
      'ibkr.portfolio',
      'secret-account-key',
      () => gate.future,
    );
    final second = coordinator.coalesce<int>(
      'ibkr.portfolio',
      'secret-account-key',
      () => Future.value(99),
    );

    expect(coordinator.startedCount('ibkr.portfolio'), 1);
    expect(coordinator.coalescedCount('ibkr.portfolio'), 1);
    expect(coordinator.activeRequestCount, 1);

    gate.complete(42);
    expect(await Future.wait([first, second]), [42, 42]);
    expect(coordinator.activeRequestCount, 0);

    await coordinator.runFresh('market.candles', 'AAPL', 'today', () async {});
    await coordinator.runFresh('market.candles', 'AAPL', 'today', () async {});

    expect(coordinator.startedCount('market.candles'), 1);
    expect(coordinator.freshSkippedCount('market.candles'), 1);
    final summary = coordinator.diagnosticsSummary(label: 'startup');
    expect(summary, contains('ibkr.portfolio started=1 coalesced=1'));
    expect(summary, contains('market.candles started=1'));
    expect(summary, isNot(contains('secret-account-key')));
  });
}
