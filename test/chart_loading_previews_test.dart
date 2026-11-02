import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/chart_loading_previews.dart';

void main() {
  testWidgets('all ten designs can be selected, animated, and paused', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ChartLoadingPreviews())),
    );
    expect(find.byType(ChoiceChip), findsNWidgets(10));
    expect(tester.hasRunningAnimations, isFalse);
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byType(ChoiceChip).at(i));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(ValueKey('loading-preview-$i')), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byTooltip('Pause preview'));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('preview stays still with reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: ChartLoadingPreviews()),
        ),
      ),
    );
    await tester.tap(find.byType(ChoiceChip).at(5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('loading-preview-5')), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
