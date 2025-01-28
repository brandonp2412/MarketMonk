import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';
import 'package:market_monk/chart_page.dart';
import 'package:market_monk/database.dart';
import 'package:market_monk/main.dart' as app;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:market_monk/utils.dart' as utils;
import 'package:market_monk/symbol.dart';

class Utils {
  Future<List<Symbol>> getSymbols() => utils.getSymbols();
}

class MockUtils extends Mock implements Utils {}

DatabaseConnection createConnection() {
  return DatabaseConnection(NativeDatabase.memory());
}

void main() {
  late MockUtils mockUtils;

  group('Screenshot:', () {
    setUp(() async {
      mockUtils = MockUtils();
      TestWidgetsFlutterBinding.ensureInitialized();

      app.db = Database.connect(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );

      SharedPreferences.setMockInitialValues({"theme": "ThemeMode.system"});

      mockUtils = MockUtils();
      when(() => mockUtils.getSymbols()).thenAnswer(
        (_) => Future.value([Symbol(value: "GME", name: "GameStop")]),
      );
    });

    tearDown(() async {
      await app.db.close();
    });

    _screenshotWidget(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      goldenFileName: '1_counter_100',
      child: const ChartPage(),
    );
  });
}

void _screenshotWidget({
  ThemeData? theme,
  required String goldenFileName,
  required Widget child,
}) {
  group(goldenFileName, () {
    for (final goldenDevice in GoldenScreenshotDevices.values) {
      testWidgets('for ${goldenDevice.name}', (tester) async {
        final now = DateTime.now();
        final mockCandles = [
          for (int i = 0; i < 5; i++)
            CandlesCompanion.insert(
              date: now.subtract(Duration(days: i)),
              symbol: 'GME',
              close: Value(100.0 + i * 10),
            ),
        ];
        await app.db.candles.insertAll(mockCandles);
        final device = goldenDevice.device;

        // Enable shadows which are normally disabled in golden tests.
        // Make sure to disable them again at the end of the test.
        debugDisableShadows = false;

        final widget = ScreenshotApp(
          theme: theme,
          device: device,
          child: child,
        );
        await tester.pumpWidget(widget);
        // Precache the images and fonts
        // so they're ready for the screenshot.
        await tester.precacheImagesInWidgetTree();
        await tester.precacheTopbarImages();

        // Pump the widget for a second to ensure animations are complete.
        await tester.pump(const Duration(milliseconds: 100)); // Add this

        // Take the screenshot and compare it to the golden file.
        await tester.expectScreenshot(device, goldenFileName);

        debugDisableShadows = true;
      });
    }
  });
}
