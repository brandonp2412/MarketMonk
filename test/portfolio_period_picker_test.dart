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
    // Discrete rounded sliders inset the thumb, but this ruler's ticks start
    // at the actual endpoints; the thumb and ticks must share coordinates.
    expect(theme.trackShape!.isRounded, isFalse);
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

    // The first, last, and every intermediate tick are interactive stops.
    final renderBox = tester.renderObject<RenderBox>(finder);
    final track = theme.trackShape!.getPreferredRect(
      parentBox: renderBox,
      sliderTheme: theme,
      isEnabled: true,
      isDiscrete: true,
    );
    for (var index = 0; index < dates.length; index++) {
      final tick = Offset(
        bounds.left + track.left + track.width * index / (dates.length - 1),
        bounds.top + track.center.dy,
      );
      await tester.tapAt(tick);
      await tester.pumpAndSettle();
      expect(selected, index);
    }
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

  testWidgets('uncached timeline repeats sweep until history is ready',
      (tester) async {
    final now = DateTime(2026, 11, 12);
    Widget picker({required bool loading}) => MaterialApp(
          home: Scaffold(
            body: PortfolioPeriodPicker(
              loading: loading,
              labels: loading ? const ['Now'] : const ['Now', '1D'],
              dates: loading
                  ? const [null]
                  : [null, now.subtract(const Duration(days: 1))],
              value: 0,
              onChanged: (_) {},
            ),
          ),
        );

    await tester.pumpWidget(picker(loading: true));
    expect(find.text('PRESENT'), findsOneWidget);
    expect(find.textContaining('FETCHING PAST PERIODS'), findsNothing);
    expect(find.text('FURTHEST · NOW'), findsNothing);
    double? sweepProgress() {
      final slider = find.byKey(const Key('portfolio-return-period'));
      final track = tester
          .widget<SliderTheme>(
            find.ancestor(of: slider, matching: find.byType(SliderTheme)).first,
          )
          .data
          .trackShape as dynamic;
      return track.loadingProgress as double?;
    }

    await tester.pump(const Duration(milliseconds: 450));
    final firstPass = sweepProgress();
    expect(firstPass, isNotNull);
    expect(firstPass!, greaterThan(0));
    expect(firstPass, lessThan(1));
    // A second cycle must revisit the same position instead of freezing at 1.
    await tester.pump(const Duration(milliseconds: 1600));
    final secondPass = sweepProgress();
    expect(secondPass, isNotNull);
    expect(secondPass!, closeTo(firstPass, 0.02));
    await tester.pump(const Duration(milliseconds: 400));
    expect(sweepProgress(), isNot(closeTo(firstPass, 0.02)));
    expect(find.text('PRESENT'), findsOneWidget);

    await tester.pumpWidget(picker(loading: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('LOADING HISTORY'), findsNothing);
    expect(find.text('PRESENT'), findsOneWidget);
    expect(find.text('FURTHEST · NOV 2026'), findsOneWidget);
    expect(sweepProgress(), isNull);
    expect(
      tester
          .widget<Slider>(
            find.byKey(const Key('portfolio-return-period')),
          )
          .onChanged,
      isNotNull,
    );
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
