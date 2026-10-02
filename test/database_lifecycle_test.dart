import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:market_monk/database.dart';
import 'package:test/test.dart';

void main() {
  test('close waits for an in-flight leased database operation', () async {
    final database = Database.connect(NativeDatabase.memory());
    final operationStarted = Completer<void>();
    final finishOperation = Completer<void>();
    var closeCompleted = false;

    final operation = database.runWhileOpen(() async {
      operationStarted.complete();
      await finishOperation.future;
      await database.trades.insertOne(
        TradesCompanion.insert(
          symbol: 'VTI',
          name: 'Vanguard Total Stock Market ETF',
          quantity: 1,
          price: 100,
          tradeType: 'open',
          tradeDate: DateTime(2026, 10, 2),
        ),
      );
    });

    await operationStarted.future;
    final close = database.close().then((_) => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);

    expect(closeCompleted, isFalse);

    finishOperation.complete();
    await operation;
    await close;

    expect(closeCompleted, isTrue);
  });

  test('new leased work is rejected once close has started', () async {
    final database = Database.connect(NativeDatabase.memory());
    final operationStarted = Completer<void>();
    final finishOperation = Completer<void>();

    final operation = database.runWhileOpen(() async {
      operationStarted.complete();
      await finishOperation.future;
    });

    await operationStarted.future;
    final close = database.close();

    await expectLater(
      database.runWhileOpen(() async {}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Database is closing',
        ),
      ),
    );

    finishOperation.complete();
    await operation;
    await close;
  });
}
