import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/market_line_chart.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/ticker_line.dart';
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
      // Previously enabled on this installation: no retired control should show.
      'showMarketClosed': true,
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

  testWidgets('settings use a two-column desktop layout on wide windows', (
    tester,
  ) async {
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
      find.ancestor(of: find.text('Language'), matching: find.byType(ListTile)),
      findsNothing,
    );
    expect(find.text('Charts'), findsWidgets);
    expect(find.text('Market closed indicator'), findsNothing);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);

    final export = tester.getTopLeft(find.text('Export database'));
    final import = tester.getTopLeft(find.text('Import database'));
    expect(export.dy, import.dy);
    expect(tester.takeException(), null);
  });

  testWidgets('settings keep desktop cards at compact desktop width', (
    tester,
  ) async {
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

  testWidgets('desktop search matches the settings content width', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1800, 900));

    final search = tester.getRect(find.byKey(const Key('settings-search')));
    final cards = tester.getRect(
      find.byKey(const Key('desktop-settings-two-column')),
    );
    expect(search.width, 1240);
    expect(search.left, closeTo(cards.left, 0.1));
    expect(search.right, closeTo(cards.right, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile search retains its page padding', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));

    final search = tester.getRect(find.byKey(const Key('settings-search')));
    expect(search.left, 16);
    expect(search.right, 414);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile Settings clears the floating bottom navigation dock', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));

    final settingsList = tester.widget<ListView>(find.byType(ListView).first);
    expect(
      settingsList.padding,
      const EdgeInsets.only(bottom: bottomNavScrollClearance),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile section headings share styling and label spacing', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));

    final general = tester.widget<Text>(find.text('General'));
    final appearance = tester.widget<Text>(find.text('Appearance'));
    expect(general.style, appearance.style);

    final sectionPadding = tester
        .widgetList<Padding>(
          find.ancestor(
            of: find.text('General'),
            matching: find.byType(Padding),
          ),
        )
        .firstWhere((padding) => padding.child is Text);
    expect(sectionPadding.padding, const EdgeInsets.fromLTRB(16, 20, 16, 12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile chart settings persist average and candle modes', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));
    final average = find.byKey(const Key('settings-rolling-average'));
    final candles = find.byKey(const Key('settings-candlestick-chart'));
    expect(
      tester.getSize(find.byKey(const Key('settings-search'))).width,
      closeTo(398, 1),
    );
    expect(average, findsOneWidget);
    expect(candles, findsOneWidget);
    expect(find.text('Market closed indicator'), findsNothing);
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

  testWidgets('chart preview follows both chart modes during settings search', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));
    final search = find.byKey(const Key('settings-search'));
    final preview = find.byKey(const Key('settings-chart-preview'));
    TickerLine ticker() => tester.widget<TickerLine>(
          find.descendant(of: preview, matching: find.byType(TickerLine)),
        );
    MarketLineChart chart() => tester.widget<MarketLineChart>(
          find.descendant(of: preview, matching: find.byType(MarketLineChart)),
        );

    await tester.enterText(search, 'moving average');
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    expect(ticker().showRollingAverage, false);
    expect(ticker().candles, isNotEmpty);
    await tester.tap(find.byKey(const Key('settings-rolling-average')));
    await tester.pumpAndSettle();
    expect(ticker().showRollingAverage, true);
    expect(chart().showRollingAverage, true);

    await tester.enterText(search, 'candles');
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    expect(ticker().showCandlesticks, false);
    await tester.tap(find.byKey(const Key('settings-candlestick-chart')));
    await tester.pumpAndSettle();
    expect(ticker().showCandlesticks, true);
    expect(chart().showCandlesticks, true);
    expect(chart().candles.length, ticker().spots.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop chart preview stays visible when filtering chart settings',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpSettings(tester, const Size(1200, 900));
      await tester.enterText(
        find.byKey(const Key('settings-search')),
        'gridlines',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-chart-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('new chart controls update persisted settings on mobile', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));
    for (final (key, setting, value) in [
      ('settings-chart-gridlines', 'showChartGridlines', true),
      ('settings-chart-shading', 'fillChartArea', false),
    ]) {
      final control = find.byKey(Key(key));
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      await tester.tap(control);
      await tester.pumpAndSettle();
      expect((await SqliteSettings.getInstance()).getBool(setting), value);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('start page choice saves from desktop settings search', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1200, 900));
    await tester.enterText(find.byKey(const Key('settings-search')), 'home');
    await tester.pumpAndSettle();
    final selector = find.byKey(const Key('settings-start-page'));
    expect(selector, findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Holdings').last);
    await tester.pumpAndSettle();
    expect((await SqliteSettings.getInstance()).getInt('startPage'), 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop search filters settings and restores them on clear', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1200, 900));

    await tester.enterText(find.byKey(const Key('settings-search')), 'IBKR');
    await tester.pumpAndSettle();
    expect(find.text('Interactive Brokers'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Currencies'), findsNothing);
    expect(find.text('Appearance'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Currencies'), findsOneWidget);
    expect(find.text('Charts'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile search filters individual controls and handles no results',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await pumpSettings(tester, const Size(430, 940));

      await tester.enterText(
        find.byKey(const Key('settings-search')),
        'candles',
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('settings-candlestick-chart')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-rolling-average')), findsNothing);
      expect(find.text('Charts'), findsOneWidget);
      expect(find.text('Appearance'), findsNothing);

      await tester.enterText(
        find.byKey(const Key('settings-search')),
        'no such setting',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching settings'), findsOneWidget);
      expect(find.text('Charts'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-rolling-average')), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop settings omit the mobile-only chart switches', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1200, 900));
    expect(find.byKey(const Key('settings-rolling-average')), findsNothing);
    expect(find.byKey(const Key('settings-candlestick-chart')), findsNothing);
    expect(find.text('Market closed indicator'), findsNothing);
  });
  testWidgets('desktop search finds common alternative settings terms', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1200, 900));
    final search = find.byKey(const Key('settings-search'));
    for (final entry in <String, String>{
      'refresh prices': 'Sync',
      'restore': 'Import database',
      'privacy': 'Hide dollar amounts',
    }.entries) {
      await tester.enterText(search, entry.key);
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget, reason: entry.key);
    }
  });

  testWidgets('mobile chart search understands common chart terminology', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(430, 940));
    final search = find.byKey(const Key('settings-search'));
    await tester.enterText(search, 'moving average');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-rolling-average')), findsOneWidget);
    expect(find.byKey(const Key('settings-candlestick-chart')), findsNothing);

    await tester.enterText(search, 'candlestick');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-candlestick-chart')), findsOneWidget);
    expect(find.byKey(const Key('settings-rolling-average')), findsNothing);
  });
  testWidgets('desktop settings search stays within content bounds',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1400, 900));
    expect(
      tester.getSize(find.byKey(const Key('settings-search'))).width,
      lessThanOrEqualTo(1240),
    );
  });

  testWidgets('date formats include long formats and hex colors persist', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1200, 900));
    final settings =
        tester.element(find.byType(SettingsPage)).read<SettingsState>();
    await settings.setSystemColors(false);
    await tester.pumpAndSettle();

    final originalColor = settings.seedColor;
    final customButton = find.byKey(const Key('theme-color-custom'));
    await tester.tap(customButton);
    await tester.pumpAndSettle();
    final hexField = find.byKey(const Key('theme-hex-field'));
    await tester.enterText(hexField, '#123ABC');
    await tester.pumpAndSettle();
    expect(settings.seedColor, originalColor);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.seedColor, originalColor);

    await tester.tap(customButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-saturation-value')));
    await tester.drag(
      find.byKey(const Key('theme-hue-slider')),
      const Offset(30, 0),
    );
    await tester.pumpAndSettle();
    expect(settings.seedColor, originalColor);
    await tester.enterText(hexField, 'invalid');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('theme-color-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(hexField, '#123ABC');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('theme-color-save')));
    await tester.pumpAndSettle();
    expect(settings.seedColor, const Color(0xFF123ABC));
    await tester.tap(customButton);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(hexField).controller!.text, '#123ABC');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('settings-search')),
      'date format',
    );
    await tester.pumpAndSettle();
    final selector = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(
      selector.items!.map((item) => item.value),
      containsAll(['d MMM yyyy', 'MMM d, yyyy', 'yyyy/MM/dd', 'dd.MM.yyyy']),
    );
  });
}
