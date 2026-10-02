import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/main.dart';
import 'package:market_monk/settings_page.dart';
import 'package:market_monk/settings_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSettings(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    SharedPreferences.setMockInitialValues({
      'systemColors': true,
    });
    PackageInfo.setMockInitialValues(
      appName: 'Market Monk',
      packageName: 'com.example.market_monk',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );

    final accounts = AccountManager();
    await accounts.init();
    final settings = SettingsState();
    await settings.initialized;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: accounts),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings use a two-column desktop layout on wide windows',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(1400, 900));

    expect(
      find.byKey(const Key('desktop-settings-two-column')),
      findsOneWidget,
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Charts'), findsOneWidget);
    expect(find.text('Accounts'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);

    final export = tester.getTopLeft(find.text('Export database'));
    final import = tester.getTopLeft(find.text('Import database'));
    expect(export.dy, import.dy);
    expect(tester.takeException(), null);
  });

  testWidgets('settings keep desktop cards at compact desktop width',
      (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpSettings(tester, const Size(880, 900));

    expect(
      find.byKey(const Key('desktop-settings-single-column')),
      findsOneWidget,
    );
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Data'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}
