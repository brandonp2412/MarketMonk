import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/ibkr_api.dart';
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
}
