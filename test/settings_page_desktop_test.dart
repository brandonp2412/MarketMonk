import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await seedTestSqlite({
      'systemColors': true,
    });
    PackageInfo.setMockInitialValues(
      appName: 'Market Monk',
      packageName: 'com.example.market_monk',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    final accounts = testAccountManager();
    await accounts.init();
    final settings = SettingsState();
    await settings.initialized;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings use a two-column desktop layout on wide windows',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1400, 900));

    expect(
      find.byKey(const Key('desktop-settings-two-column')),
      findsOneWidget,
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Hide dollar amounts'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Language'),
        matching: find.byType(ListTile),
      ),
      findsNothing,
    );
    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);

    final export = tester.getTopLeft(find.text('Export database'));
    final import = tester.getTopLeft(find.text('Import database'));
    expect(export.dy, import.dy);
    expect(tester.takeException(), null);
  });

  testWidgets('settings keep desktop cards at compact desktop width',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(880, 900));

    expect(
      find.byKey(const Key('desktop-settings-single-column')),
      findsOneWidget,
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('mobile chart settings persist average and candle modes',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));
    final average = find.byKey(const Key('settings-rolling-average'));
    final candles = find.byKey(const Key('settings-candlestick-chart'));
    expect(average, findsOneWidget);
    expect(candles, findsOneWidget);
    await tester.ensureVisible(average);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: average, matching: find.byType(Switch)),
          )
          .value,
      false,
    );
    await tester.tap(average);
    await tester.pumpAndSettle();
    expect(
      (await SqliteSettings.getInstance()).getBool('chartRollingAverage'),
      true,
    );

    await tester.ensureVisible(candles);
    await tester.pumpAndSettle();
    await tester.tap(candles);
    await tester.pumpAndSettle();
    expect(
      (await SqliteSettings.getInstance()).getBool('chartCandlesticks'),
      true,
    );
    expect(
      tester
          .widget<Switch>(
            find.descendant(of: candles, matching: find.byType(Switch)),
          )
          .value,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop settings omit the mobile-only chart switches',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1200, 900));
    expect(find.byKey(const Key('settings-rolling-average')), findsNothing);
    expect(find.byKey(const Key('settings-candlestick-chart')), findsNothing);
  });
}
