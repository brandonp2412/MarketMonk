import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database syncDatabase;
  late Database cacheDatabase;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('monk-concurrency-');
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    final profileName =
        directory.uri.pathSegments.where((part) => part.isNotEmpty).last;
    syncDatabase = Database(profileName);
    cacheDatabase = Database(profileName);
    await syncDatabase.select(syncDatabase.candles).get();
    await cacheDatabase.select(cacheDatabase.ibkrCacheEntries).get();
  });

  tearDown(() async {
    await cacheDatabase.close();
    await syncDatabase.close();
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('portfolio cache waits for a candle transaction on the same profile',
      () async {
    final transactionStarted = Completer<void>();
    final releaseTransaction = Completer<void>();
    final sync = syncDatabase.transaction(() async {
      await syncDatabase.candles.insertOne(
        CandlesCompanion.insert(
          symbol: 'VTI',
          date: DateTime(2026),
          close: const Value(100),
        ),
      );
      transactionStarted.complete();
      await releaseTransaction.future;
    });
    await transactionStarted.future;
    final cacheOutcome = cacheDatabase
        .writeIbkrCache(
          kind: 'portfolio',
          cacheKey: 'snapshot',
          payloadJson: '{}',
          cachedAt: DateTime(2026),
        )
        .then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace stack) => error,
        );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    releaseTransaction.complete();
    await sync;
    expect(await cacheOutcome, null);
    expect(
      await cacheDatabase.readIbkrCache('portfolio', 'snapshot'),
      isNotNull,
    );
    await cacheDatabase.close();
    expect(await syncDatabase.select(syncDatabase.candles).get(), hasLength(1));
  });

  test('trade watchers observe commits from another client of the same profile',
      () async {
    final initialRead = Completer<void>();
    final changed = Completer<List<Trade>>();
    final subscription =
        syncDatabase.select(syncDatabase.trades).watch().listen((rows) {
      if (!initialRead.isCompleted) initialRead.complete();
      if (rows.isNotEmpty && !changed.isCompleted) changed.complete(rows);
    });
    addTearDown(subscription.cancel);
    await initialRead.future;
    await cacheDatabase.trades.insertOne(
      TradesCompanion.insert(
        symbol: 'VTI',
        name: 'VTI',
        quantity: 1,
        price: 100,
        tradeType: 'open',
        tradeDate: DateTime(2026),
      ),
    );
    expect(
      (await changed.future.timeout(const Duration(seconds: 3))).single.symbol,
      'VTI',
    );
  });
}
