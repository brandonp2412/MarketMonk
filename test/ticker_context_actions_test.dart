import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/desktop_context_menu.dart';
import 'package:market_monk/charts_page.dart';
import 'package:market_monk/ibkr_api.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/ticker_context_actions.dart';
import 'package:provider/provider.dart';
import 'sqlite_test_support.dart';

void main() {
  for (final managed in [false, true]) {
    testWidgets('ticker actions persist favorites and respect IBKR=$managed',
        (tester) async {
      await seedTestSqlite({});
      final accounts = testAccountManager();
      await accounts.init();
      if (managed) {
        await accounts.setIbkrConfig(
          'Default',
          const IbkrAccountConfig(
            enabled: true,
            baseUrl: 'https://ibkr.example.test',
            token: 'test-token',
          ),
        );
      }
      late BuildContext menuContext;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: accounts,
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                menuContext = context;
                return const Scaffold(body: Text('VOO'));
              },
            ),
          ),
        ),
      );
      final actions = await tickerContextActions(menuContext, 'VOO');
      expect(
        actions.map((action) => action.label),
        containsAll(['Open chart', 'Add favorite']),
      );
      expect(actions.any((action) => action.label == 'Add trade'), !managed);
      actions
          .singleWhere((action) => action.label == 'Add favorite')
          .onSelected!();
      await tester.pumpAndSettle();
      final settings = await SqliteSettings.getInstance();
      expect(settings.getStringList('favoriteStocks'), contains('VOO'));
      final updated = await tickerContextActions(menuContext, 'VOO');
      expect(
        updated.map((action) => action.label),
        contains('Remove favorite'),
      );
      updated
          .singleWhere((action) => action.label == 'Remove favorite')
          .onSelected!();
      await tester.pumpAndSettle();
      expect(settings.getStringList('favoriteStocks'), isNot(contains('VOO')));
    });
  }

  testWidgets('open chart requests the charts tab focus on desktop',
      (tester) async {
    await seedTestSqlite({});
    final accounts = testAccountManager();
    await accounts.init();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: accounts,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: DesktopContextMenu(
                  actionsBuilder: () => tickerContextActions(context, 'VOO'),
                  child: const SizedBox(
                    width: 200,
                    height: 100,
                    child: Text('VOO'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final focused = <String>[];
    final subscription =
        ChartsFocusController.instance.requests.listen(focused.add);
    addTearDown(subscription.cancel);

    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(tester.getCenter(find.text('VOO')));
    await mouse.up();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open chart'));
    await tester.pump();
    await tester.pump();

    expect(focused, ['VOO']);
    expect(find.byType(ChartsPage), findsNothing);
  });
}
