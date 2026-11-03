import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/portfolio_period_picker.dart';

void main() {
  testWidgets('period picker snaps while dragging and uses a dotted track',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PortfolioPeriodPicker(
              labels: const ['All time', '3M', '1M', '1W', '1D'],
              value: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );
    final finder = find.byKey(const Key('portfolio-return-period'));
    final slider = tester.widget<Slider>(finder);
    final theme = SliderTheme.of(tester.element(finder));
    expect(theme.trackShape.runtimeType.toString(), '_DottedPeriodTrack');
    expect(theme.thumbShape, isA<RoundSliderThumbShape>());
    expect(theme.tickMarkShape, SliderTickMarkShape.noTickMark);
    final bounds = tester.getRect(finder);
    final gesture =
        await tester.startGesture(Offset(bounds.left + 24, bounds.center.dy));
    await gesture.moveTo(Offset(bounds.right - 24, bounds.center.dy));
    await tester.pump();
    expect(selected, 4);
    expect(find.text('1D'), findsOneWidget);
    await gesture.up();
    expect(slider.divisions, 4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no alternative period leaves the picker disabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioPeriodPicker(
            labels: const ['All time'],
            value: 0,
            onChanged: (_) => fail('No available periods'),
          ),
        ),
      ),
    );
    final slider =
        tester.widget<Slider>(find.byKey(const Key('portfolio-return-period')));
    expect(slider.onChanged, isNull);
    expect(find.text('All time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
