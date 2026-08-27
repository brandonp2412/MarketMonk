import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/whats_new.dart';

void main() {
  testWidgets("What's New loads bundled release notes", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WhatsNew()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });
}
