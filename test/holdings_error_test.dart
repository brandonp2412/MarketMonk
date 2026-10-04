import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/crash_logger.dart';
import 'package:market_monk/holdings_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_state.dart';
import 'package:market_monk/utils.dart';
import 'package:provider/provider.dart';

import 'sqlite_test_support.dart';

class _FailedCacheAccountManager extends AccountManager {
  final failure = StateError('database is locked; private cache payload');

  @override
  Future<void> cachePortfolio(
    String name,
    List<Position> positions,
    IbkrAccountValue? netLiquidation, {
    double? netLiquidationUsd,
  }) async =>
      throw failure;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> prepare(WidgetTester tester) async {
    await seedTestSqlite({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget app(AccountManager accounts, HoldingsPage page) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsState()),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: MaterialApp(home: page),
      );

  testWidgets(
      'load errors reach Flutter, Talker and crash log without exposing SQL',
      (tester) async {
    await prepare(tester);
    final logDirectory = Directory.systemTemp.createTempSync('monk-error-log-');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => logDirectory.path);
    final failure =
        StateError('SQLITE_BUSY INSERT private portfolio parameters');
    final previousFlutterOnError = FlutterError.onError;
    final previousPlatformOnError =
        WidgetsBinding.instance.platformDispatcher.onError;
    final reported = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      if (identical(details.exception, failure)) {
        reported.add(details);
      } else {
        previousFlutterOnError?.call(details);
      }
    };
    await tester.runAsync(() => CrashLogger.install(fileName: 'holdings.log'));
    installTalkerErrorHandlers();
    addTearDown(() {
      FlutterError.onError = previousFlutterOnError;
      WidgetsBinding.instance.platformDispatcher.onError =
          previousPlatformOnError;
      messenger.setMockMethodCallHandler(channel, null);
      logDirectory.deleteSync(recursive: true);
    });
    final recoveredPosition = Position(
      symbol: 'VTI',
      name: 'Vanguard',
      nativeCurrency: 'USD',
      netShares: 1,
      avgCost: 100,
      currentPrice: 101,
      firstBuyDate: DateTime(2026),
      lastBuyDate: DateTime(2026),
    );
    var fail = true;
    await tester.pumpWidget(
      app(
        testAccountManager(),
        HoldingsPage(
          positionsLoader: (_) async {
            if (fail) throw failure;
            return [recoveredPosition];
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Couldn’t load holdings'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private portfolio'), findsNothing);
    expect(
      reported.any(
        (details) =>
            identical(details.exception, failure) &&
            details.context.toString().contains('loading holdings'),
      ),
      true,
    );
    expect(
      talker.history.any((entry) => identical(entry.error, failure)),
      true,
    );
    final log = File('${logDirectory.path}/holdings.log').readAsStringSync();
    expect(log, contains('(FlutterError)'));
    expect(log, contains('SQLITE_BUSY INSERT private portfolio parameters'));
    expect(log, contains('holdings_error_test.dart'));
    final reportsBeforeRebuild = reported.length;
    await tester.pump();
    expect(reported.length, reportsBeforeRebuild);

    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Couldn’t load holdings'), findsNothing);
    expect(find.text('VTI'), findsOneWidget);
    expect(
      reported.where((details) => !identical(details.exception, failure)),
      isEmpty,
    );
  });

  testWidgets('cache failure is reported but fetched holdings remain visible',
      (tester) async {
    await prepare(tester);
    final accounts = _FailedCacheAccountManager();
    final reported = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (identical(details.exception, accounts.failure)) {
        reported.add(details);
      } else {
        previousOnError?.call(details);
      }
    };
    addTearDown(() => FlutterError.onError = previousOnError);
    cacheSymbolMeta('VTI', 'USD');
    await seedTestTrade(
      symbol: 'VTI',
      name: 'Vanguard',
      quantity: 2,
      price: 100,
      tradeType: 'open',
      tradeDate: DateTime(2026),
    );
    await seedTestCandle('VTI', DateTime.now(), 120);
    await tester.pumpWidget(app(accounts, const HoldingsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('VTI'), findsOneWidget);
    expect(find.text('Couldn’t load holdings'), findsNothing);
    expect(find.textContaining('private cache payload'), findsNothing);
    expect(
      reported.any(
        (details) =>
            identical(details.exception, accounts.failure) &&
            details.context.toString().contains('saving the holdings cache'),
      ),
      true,
    );
    expect(
      reported.where(
        (details) => !identical(details.exception, accounts.failure),
      ),
      isEmpty,
    );
  });
}
