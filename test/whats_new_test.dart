import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/whats_new.dart';

void main() {
  testWidgets("What's New displays bundled release notes", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WhatsNew()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("What's New"), findsOneWidget);
    expect(find.text('Unable to load release notes.'), findsNothing);
    expect(find.text('No release notes available'), findsNothing);
  });
}
