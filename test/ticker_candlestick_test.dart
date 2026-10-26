import 'package:drafter/drafter.dart';
import 'package:drafter/painting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:market_monk/ticker_candlestick.dart';
import 'package:market_monk/utils.dart';

void main() {
  PriceCandle bar(
    int day,
    double open,
    double high,
    double low,
    double close,
  ) =>
      PriceCandle(
        date: DateTime(2026, 10, day),
        open: open,
        high: high,
        low: low,
        close: close,
      );

  test('aggregates real OHLC instead of averaging closing prices', () {
    final result = aggregatePriceCandles(
      [
        bar(1, 10, 15, 9, 12),
        bar(2, 12, 18, 8, 16),
        bar(3, 16, 17, 14, 15),
        bar(4, 15, 19, 13, 18),
      ],
      2,
    );

    expect(result, hasLength(2));
    expect(result.first.open, 10);
    expect(result.first.high, 18);
    expect(result.first.low, 8);
    expect(result.first.close, 16);
    expect(result.last.close, 18);
    expect(result.last.high, 19);
  });

  test('ignores missing or inconsistent OHLC observations', () {
    final result = aggregatePriceCandles(
      [
        bar(1, -1, -1, -1, 12),
        bar(2, 10, 9, 8, 12),
        bar(3, 10, 12, 8, 11),
      ],
      5,
    );
    expect(result, hasLength(1));
    expect(result.single.close, 11);
  });

  testWidgets('uses display-currency prices and shows a tappable OHLC readout',
      (tester) async {
    final oldCurrency = currency;
    final oldRates = Map<String, double>.of(allRatesFromUsd);
    currency = NumberFormat.simpleCurrency(name: 'NZD');
    allRatesFromUsd['NZD'] = 1.5;
    addTearDown(() {
      currency = oldCurrency;
      allRatesFromUsd = oldRates;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 240,
            child: TickerCandlestick(
              nativeCurrency: 'USD',
              showRollingAverage: true,
              candles: [
                for (var day = 1; day <= 25; day++) bar(day, 100, 105, 95, 101),
              ],
            ),
          ),
        ),
      ),
    );

    final canvas = tester.widget<ChartCanvas>(find.byType(ChartCanvas));
    final renderer = canvas.renderer as CandlestickChartRenderer;
    expect(renderer.candles, hasLength(25));
    expect(renderer.candles.first.open, 150);
    expect(renderer.candles.first.low, 142.5);
    expect(renderer.movingAverages.single.period, 20);

    final origin = tester.getTopLeft(find.byType(ChartCanvas));
    final scene = renderer.buildScene(const Size(320, 240));
    await tester.tapAt(origin + scene.marks.first.center);
    await tester.pump();
    expect(find.byKey(const Key('candle-price-tooltip')), findsOneWidget);
    expect(find.textContaining('1 Oct 2026'), findsOneWidget);
    expect(find.textContaining(fmtNativeCurrency(100, 'USD')), findsOneWidget);

    final gesture =
        await tester.startGesture(origin + scene.marks.first.center);
    await gesture.moveTo(origin + scene.marks.last.center);
    await tester.pump();
    expect(find.textContaining('25 Oct 2026'), findsOneWidget);
    await gesture.up();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press scrub keeps the surrounding page in place',
      (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageView(
            controller: controller,
            children: [
              TickerCandlestick(
                nativeCurrency: 'USD',
                candles: [
                  for (var day = 1; day <= 25; day++)
                    bar(
                      day,
                      100 + day.toDouble(),
                      110 + day.toDouble(),
                      95,
                      105 + day.toDouble(),
                    ),
                ],
              ),
              const Center(child: Text('Other tab')),
            ],
          ),
        ),
      ),
    );
    final finder = find.byType(ChartCanvas);
    final canvas = tester.widget<ChartCanvas>(finder);
    final scene = (canvas.renderer as CandlestickChartRenderer)
        .buildScene(tester.getSize(finder));
    final center = tester.getTopLeft(finder) + scene.marks[12].center;
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 650));
    await gesture.moveBy(const Offset(-240, 0));
    await tester.pump();
    expect(controller.page, closeTo(0, 0.01));
    expect(find.byKey(const Key('candle-price-tooltip')), findsOneWidget);
    final index = ChartHitTest.nearestIndexAtX(scene, center.dx - 240);
    expect(find.textContaining('${index! + 1} Oct 2026'), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.page, closeTo(0, 0.01));
  });
}
