import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/ticker_search_loading.dart';

void main() {
  testWidgets('ticker search loader respects motion settings and disposes',
      (tester) async {
    Future<void> mount(bool reducedMotion) => tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: const Scaffold(body: Center(child: TickerSearchLoading())),
            ),
          ),
        );

    await mount(false);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.bySemanticsLabel('Search'), findsOneWidget);

    await mount(true);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await mount(false);
    await tester.pump(const Duration(milliseconds: 450));
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
