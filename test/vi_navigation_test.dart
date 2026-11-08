import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/vi_navigation.dart';

void main() {
  tearDown(() {
    ViNavigation.instance.target = null;
    ModalRouteTracker.instance.modalDepth = 0;
  });

  group('viFocusIndex', () {
    test('empty list has no focus', () {
      expect(viFocusIndex(-1, 1, 0), -1);
      expect(viFocusIndex(0, -1, 0), -1);
    });

    test('first move from no focus lands on an end', () {
      expect(viFocusIndex(-1, 1, 3), 0);
      expect(viFocusIndex(-1, -1, 3), 2);
    });

    test('moves one step at a time', () {
      expect(viFocusIndex(0, 1, 3), 1);
      expect(viFocusIndex(2, -1, 3), 1);
    });

    test('clamps at both ends without wrapping', () {
      expect(viFocusIndex(2, 1, 3), 2);
      expect(viFocusIndex(0, -1, 3), 0);
      expect(viFocusIndex(0, 10, 3), 2);
      expect(viFocusIndex(2, -10, 3), 0);
    });
  });

  group('ModalRouteTracker', () {
    testWidgets('counts modal pushes and pops', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [ModalRouteTracker.instance],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    content: Text('dialog'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      expect(ModalRouteTracker.instance.modalDepth, 0);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(ModalRouteTracker.instance.modalDepth, 1);

      Navigator.pop(tester.element(find.text('dialog')));
      await tester.pumpAndSettle();
      expect(ModalRouteTracker.instance.modalDepth, 0);
    });

    testWidgets('counts page pushes like dialogs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [ModalRouteTracker.instance],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Text('page')),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(ModalRouteTracker.instance.modalDepth, 1);

      Navigator.pop(tester.element(find.text('page')));
      await tester.pumpAndSettle();
      expect(ModalRouteTracker.instance.modalDepth, 0);
    });
  });
}
