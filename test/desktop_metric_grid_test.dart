import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/adaptive_layout.dart';

void main() {
  for (final width in [820.0, 1350.0]) {
    testWidgets('five desktop metric cards fit at width $width',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: desktopMetricGrid(
              minCardWidth: 235,
              cards: [
                for (var index = 0; index < 5; index++)
                  Expanded(
                    child: SizedBox(
                      height: 88,
                      child: Text('metric-$index'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),);
      expect(find.text('metric-0'), findsOneWidget);
      expect(find.text('metric-4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final first = tester.getTopLeft(find.text('metric-0'));
      final last = tester.getTopLeft(find.text('metric-4'));
      if (width < 1000) {
        expect(last.dy, greaterThan(first.dy));
      } else {
        expect(last.dy, first.dy);
      }
    });
  }
}
