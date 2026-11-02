import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/market_chart_loading.dart';

void main() {
  testWidgets('chart loader animates and respects reduced motion',
      (tester) async {
    Future<void> mount(bool reducedMotion) => tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: const Scaffold(body: Center(child: MarketChartLoading())),
            ),
          ),
        );

    await mount(false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.bySemanticsLabel('Refresh'), findsOneWidget);
    await mount(true);
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byType(MarketChartLoading), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
