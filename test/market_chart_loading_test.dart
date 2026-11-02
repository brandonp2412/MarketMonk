import 'dart:async';

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

  testWidgets('pull refresh shows chart loader until refresh completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarketChartRefreshIndicator(
            onRefresh: () {
              calls++;
              return pending.future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 100, child: Text('Chart'))],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(MarketChartLoading), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    expect(find.byType(MarketChartLoading), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MarketChartLoading), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
