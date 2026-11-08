import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/portfolio_period_picker.dart';

void main() {
  testWidgets('timeline starts at Now and travels back through account history',
      (tester) async {
    var selected = 0;
    final today = DateTime(2026, 11, 3);
    final dates = [
      null,
      today.subtract(const Duration(days: 1)),
      today.subtract(const Duration(days: 7)),
      DateTime(2026, 9, 3),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PortfolioPeriodPicker(
              labels: const ['Now', '1D', '1W', '2M'],
              dates: dates,
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
    expect(slider.value, 0);
    expect(slider.divisions, 3);
    expect(theme.trackShape.runtimeType.toString(), '_TimeRulerTrack');
    expect(theme.tickMarkShape, SliderTickMarkShape.noTickMark);
    expect(find.text('WHEN'), findsOneWidget);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('FURTHEST · SEP 2026'), findsOneWidget);
    expect(slider.semanticFormatterCallback!(0), 'Now, current allocation');
    expect(slider.semanticFormatterCallback!(3), contains('September 3, 2026'));

    final bounds = tester.getRect(finder);
    final gesture =
        await tester.startGesture(Offset(bounds.left + 24, bounds.center.dy));
    await gesture.moveTo(Offset(bounds.right - 24, bounds.center.dy));
    await tester.pump();
    expect(selected, 3);
    expect(
      find.text(DateFormat('d MMM yyyy').format(dates.last!)),
      findsOneWidget,
    );
    expect(
      find.text('Allocation then · returns since this date'),
      findsOneWidget,
    );
    await gesture.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('intraday periods display the exact cutoff time', (tester) async {
    final now = DateTime(2026, 11, 8, 15, 30);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioPeriodPicker(
            labels: const ['Now', '12H', '1H'],
            dates: [
              null,
              now.subtract(const Duration(hours: 12)),
              now.subtract(const Duration(hours: 1)),
            ],
            value: 2,
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('8 Nov 2026, 2:30 PM'), findsOneWidget);
    expect(find.text('FURTHEST · 8 NOV 2:30 PM'), findsOneWidget);
    expect(find.text('1H AGO'), findsOneWidget);
  });

  testWidgets('one available instant leaves the timeline disabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortfolioPeriodPicker(
            labels: const ['Now'],
            dates: const [null],
            value: 0,
            onChanged: (_) => fail('No available dates'),
          ),
        ),
      ),
    );
    final slider =
        tester.widget<Slider>(find.byKey(const Key('portfolio-return-period')));
    expect(slider.onChanged, isNull);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('FURTHEST · NOW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
