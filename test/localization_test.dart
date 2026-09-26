import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:market_monk/bottom_nav.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/l10n/translations.dart';
import 'package:market_monk/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'visibleCurrencies': ['USD'],
      'displayCurrency': 'USD',
      'exchangeRate_USD': 1.0,
    });
  });

  test(
    'every supported non-English locale has the complete translation set',
    () {
      final translatedLanguages = AppLocalizations.supportedLocales
          .map((locale) => locale.languageCode)
          .where((language) => language != 'en')
          .toSet();

      expect(appTranslations.keys.toSet(), translatedLanguages);

      final coreKeys = appTranslations['de']!.keys.toSet();
      expect(coreKeys, hasLength(44));

      for (final entry in appTranslations.entries) {
        expect(
          entry.value.keys.toSet(),
          containsAll(coreKeys),
          reason: '${entry.key} must preserve the core translation key set',
        );
      }

      expect(appTranslations['es']!.length, greaterThan(coreKeys.length));
      expect(
        appTranslations['pt']!.keys.toSet(),
        appTranslations['es']!.keys.toSet(),
        reason: 'Brazilian Portuguese must cover the complete localized UI',
      );
    },
  );

  test('localized templates preserve named placeholders', () {
    const spanish = AppLocalizations(Locale('es'));
    const brazilianPortuguese = AppLocalizations(Locale('pt', 'BR'));

    expect(
      spanish.text('Date format ({example})', {'example': '24/09/26'}),
      'Formato de fecha (24/09/26)',
    );
    expect(
      brazilianPortuguese.text('Delete {count} holdings?', {'count': 3}),
      'Excluir 3 posições?',
    );
  });

  test('Brazilian Portuguese selection resolves to pt-BR', () async {
    final settings = SettingsState();
    await settings.initialized;

    await settings.setLanguageCode('pt');

    expect(settings.locale, const Locale('pt', 'BR'));
  });

  test(
    'language preference persists and can return to system default',
    () async {
      final settings = SettingsState();
      await settings.initialized;

      expect(settings.locale, isNull);

      await settings.setLanguageCode('es');
      expect(settings.locale, const Locale('es'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('languageCode'), 'es');

      final reloaded = SettingsState();
      await reloaded.initialized;
      expect(reloaded.locale, const Locale('es'));

      await reloaded.setLanguageCode(null);
      expect(reloaded.locale, isNull);
      expect(prefs.getString('languageCode'), isNull);
    },
  );

  testWidgets('navigation labels follow the selected locale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('es'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: BottomNav(
            tabs: const ['ChartPage', 'PortfolioPage', 'HoldingsPage'],
            currentIndex: 0,
            onTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Gráficos'), findsOneWidget);
    expect(find.bySemanticsLabel('Cartera'), findsOneWidget);
    expect(find.bySemanticsLabel('Posiciones'), findsOneWidget);
  });

  test('unsupported saved language falls back to the system locale', () async {
    SharedPreferences.setMockInitialValues({
      'languageCode': 'xx',
      'visibleCurrencies': ['USD'],
      'displayCurrency': 'USD',
      'exchangeRate_USD': 1.0,
    });

    final settings = SettingsState();
    await settings.initialized;

    expect(settings.locale, isNull);
  });
}
