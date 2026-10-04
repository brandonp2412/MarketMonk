import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/database.dart';
import 'test_log_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Database writer;
  late Database reader;
  const profileId = 'profile-default';
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    allowMultipleDriftDatabasesForTest();
    directory = await Directory.systemTemp.createTemp('monk-concurrency-');
    messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
    writer = Database();
    reader = Database();
    await writer.upsertProfile(
      id: profileId,
      name: 'Default',
      sortOrder: 0,
    );
    await writer.setActiveProfileId(profileId);
    await writer.select(writer.candles).get();
    await reader.select(reader.ibkrCacheEntries).get();
  });

  tearDown(() async {
    await reader.close();
    await writer.close();
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('IBKR cache waits for a candle transaction on the same database',
      () async {
    final transactionStarted = Completer<void>();
    final releaseTransaction = Completer<void>();
    final write = writer.transaction(() async {
      await writer.candles.insertOne(
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

    final cacheOutcome = reader
        .writeIbkrCache(
          profileId: profileId,
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
    await write;
    expect(await cacheOutcome, null);
    expect(
      await reader.readIbkrCache(profileId, 'portfolio', 'snapshot'),
      isNotNull,
    );
    expect(await writer.select(writer.candles).get(), hasLength(1));
  });

  test('trade watchers observe commits from another client', () async {
    final initialRead = Completer<void>();
    final changed = Completer<List<StoredTrade>>();
    final subscription = writer.select(writer.trades).watch().listen((rows) {
      if (!initialRead.isCompleted) initialRead.complete();
      if (rows.isNotEmpty && !changed.isCompleted) changed.complete(rows);
    });
    addTearDown(subscription.cancel);
    await initialRead.future;

    await reader.trades.insertOne(
      TradesCompanion.insert(
        profileId: profileId,
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
