import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/settings_state.dart';

import 'sqlite_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('new installations default to the golden monk icon seed', () async {
    await seedTestSqlite({});
    final settings = SettingsState(localCurrencyDetector: () async => 'USD');
    await settings.initialized;

    expect(settings.seedColor, defaultSeedColor);
    expect(settings.seedColor, const Color(0xFFFFB52E));
    expect(settings.systemColors, isFalse);
    await pumpEventQueue();
    settings.dispose();
  });

  test('explicitly saved theme seed colors remain unchanged', () async {
    await seedTestSqlite({'seedColor': 0xFF1976D2});
    final settings = SettingsState(localCurrencyDetector: () async => 'USD');
    await settings.initialized;

    expect(settings.seedColor, const Color(0xFF1976D2));
    await pumpEventQueue();
    settings.dispose();
  });

  test('gold can be selected and persists like other seed colors', () async {
    await seedTestSqlite({'seedColor': 0xFF2B7A78});
    final settings = SettingsState(localCurrencyDetector: () async => 'USD');
    await settings.initialized;
    await settings.setSeedColor(defaultSeedColor);

    expect(settings.seedColor, defaultSeedColor);
    expect(
      (await SqliteSettings.getInstance()).getInt('seedColor'),
      0xFFFFB52E,
    );
    await pumpEventQueue();
    settings.dispose();
  });
}
