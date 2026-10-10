import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/desktop_context_menu.dart';

void main() {
  Future<void> rightClick(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(tester.getCenter(target));
    await mouse.up();
    await tester.pumpAndSettle();
  }

  testWidgets('secondary click offers actions without firing primary click',
      (tester) async {
    var primary = 0;
    var action = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.linux),
        home: Scaffold(
          body: DesktopContextMenu(
            actions: [DesktopMenuAction('Edit trade', () => action++)],
            child: ListTile(title: const Text('Trade'), onTap: () => primary++),
          ),
        ),
      ),
    );
    await rightClick(tester, find.text('Trade'));
    expect(primary, 0);
    expect(action, 0);
    await tester.tap(find.text('Edit trade'));
    await tester.pumpAndSettle();
    expect(action, 1);
    await tester.tap(find.text('Trade'));
    expect(primary, 1);
  });

  testWidgets('inner menus win over the page menu and copy the item text',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: DesktopContextMenu(
            actions: [DesktopMenuAction('Refresh', () {})],
            child: DesktopContextMenu(
              actions: const [],
              copyText: 'AAPL: 123',
              child:
                  const SizedBox(width: 300, height: 100, child: Text('AAPL')),
            ),
          ),
        ),
      ),
    );
    await rightClick(tester, find.text('AAPL'));
    expect(find.text('Refresh'), findsNothing);
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, 'AAPL: 123');
  });

  testWidgets('touch platforms keep their existing interactions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(
          body: DesktopContextMenu(
            actions: [DesktopMenuAction('Edit trade', () {})],
            child: const Text('Trade'),
          ),
        ),
      ),
    );
    await rightClick(tester, find.text('Trade'));
    expect(find.text('Edit trade'), findsNothing);
  });
}
