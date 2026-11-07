import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/whats_new.dart';

void main() {
  test(
    'release history covers tagged versions',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final releases = jsonDecode(
        await rootBundle.loadString('assets/release_history.json'),
      ) as List<dynamic>;
      expect(releases.length, 109);
      expect(
        (releases.first as Map<String, dynamic>)['version'],
        '1.0.114',
      );
      expect((releases[1] as Map<String, dynamic>)['version'], '1.0.113');
      expect((releases.last as Map<String, dynamic>)['version'], '1.0.2+3');
      final versions = releases
          .cast<Map<String, dynamic>>()
          .map((release) => release['version'])
          .toSet();
      for (final version in [
        '1.0.14',
        '1.0.21',
        '1.0.22',
        '1.0.23',
        '1.0.24',
        '1.0.25',
      ]) {
        expect(versions, contains(version));
      }
      for (final release in releases.cast<Map<String, dynamic>>()) {
        expect(release['sourceUrl'], startsWith('https://github.com/'));
        expect(release['changes'], isA<List<dynamic>>());
      }
    },
  );

  testWidgets("What's New loads more releases at the bottom", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WhatsNew()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text("What's New"), findsOneWidget);
    expect(find.text('1.0.114'), findsOneWidget);
    expect(find.text('Unable to load release notes.'), findsNothing);

    final scrollable = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.byKey(const Key('load-more-releases')),
      300,
      scrollable: scrollable,
    );
    await tester.ensureVisible(find.byKey(const Key('load-more-releases')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 10 of 109 releases'), findsOneWidget);

    final before = tester.state<ScrollableState>(scrollable).position.pixels;
    await tester.tap(find.byKey(const Key('load-more-releases')));
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      closeTo(before, 1),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('load-more-releases')),
      300,
      scrollable: scrollable,
    );
    await tester.ensureVisible(find.byKey(const Key('load-more-releases')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 20 of 109 releases'), findsOneWidget);
  });
}
