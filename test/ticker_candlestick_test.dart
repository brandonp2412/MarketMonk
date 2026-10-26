import 'package:drafter/drafter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/ticker_candlestick.dart';

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

  testWidgets('uses Drafter OHLC renderer and moving average', (tester) async {
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

    final chart =
        tester.widget<InteractiveChart>(find.byType(InteractiveChart));
    final renderer = chart.renderer as CandlestickChartRenderer;
    expect(renderer.candles, hasLength(25));
    expect(renderer.candles.first.open, 100);
    expect(renderer.candles.first.low, 95);
    expect(renderer.movingAverages.single.period, 20);
    expect(
      chart.interaction.rowLabel!(
        renderer.buildScene(const Size(320, 240)).marks.first,
      ),
      contains('O'),
    );
    expect(tester.takeException(), isNull);
  });
}
