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
          .map(AppLocalizations.localeKey)
          .where((language) => language != 'en')
          .toSet();

      expect(appTranslations.keys.toSet(), translatedLanguages);

      final completeKeys = appTranslations['es']!.keys.toSet();
      expect(completeKeys, hasLength(185));
      expect(
        appTranslations['hi']!.keys.toSet(),
        completeKeys,
        reason: 'Hindi must cover the complete localized UI',
      );
      expect(
        appTranslations['ar']!.keys.toSet(),
        completeKeys,
        reason: 'Arabic must cover the complete localized UI',
      );
      expect(
        appTranslations['ru']!.keys.toSet(),
        completeKeys,
        reason: 'Russian must cover the complete localized UI',
      );
      expect(
        appTranslations['id']!.keys.toSet(),
        completeKeys,
        reason: 'Indonesian must cover the complete localized UI',
      );
      expect(
        appTranslations['tr']!.keys.toSet(),
        completeKeys,
        reason: 'Turkish must cover the complete localized UI',
      );
      expect(
        appTranslations['th']!.keys.toSet(),
        completeKeys,
        reason: 'Thai must cover the complete localized UI',
      );
      expect(
        appTranslations['vi']!.keys.toSet(),
        completeKeys,
        reason: 'Vietnamese must cover the complete localized UI',
      );
      expect(
        appTranslations['de']!.keys.toSet(),
        completeKeys,
        reason: 'German must cover the complete localized UI',
      );
      expect(
        appTranslations['pt']!.keys.toSet(),
        completeKeys,
        reason: 'Brazilian Portuguese must cover the complete localized UI',
      );
      expect(
        appTranslations['pl']!.keys.toSet(),
        completeKeys,
        reason: 'Polish must cover the complete localized UI',
      );
      expect(
        appTranslations['nl']!.keys.toSet(),
        completeKeys,
        reason: 'Dutch must cover the complete localized UI',
      );
      expect(
        appTranslations['fr']!.keys.toSet(),
        completeKeys,
        reason: 'French must cover the complete localized UI',
      );
      expect(
        appTranslations['ja']!.keys.toSet(),
        completeKeys,
        reason: 'Japanese must cover the complete localized UI',
      );
      expect(
        appTranslations['ko']!.keys.toSet(),
        completeKeys,
        reason: 'Korean must cover the complete localized UI',
      );
      expect(
        appTranslations['zh-Hans']!.keys.toSet(),
        completeKeys,
        reason: 'Simplified Chinese must cover the complete localized UI',
      );
      expect(
        appTranslations['zh-Hant']!.keys.toSet(),
        completeKeys,
        reason: 'Traditional Chinese must cover the complete localized UI',
      );
    },
  );

  test('localized templates preserve named placeholders', () {
    const german = AppLocalizations(Locale('de'));
    const spanish = AppLocalizations(Locale('es'));
    const brazilianPortuguese = AppLocalizations(Locale('pt', 'BR'));
    const french = AppLocalizations(Locale('fr'));
    const japanese = AppLocalizations(Locale('ja'));
    const korean = AppLocalizations(Locale('ko'));
    const arabic = AppLocalizations(Locale('ar'));
    const russian = AppLocalizations(Locale('ru'));
    const indonesian = AppLocalizations(Locale('id'));
    const turkish = AppLocalizations(Locale('tr'));
    const vietnamese = AppLocalizations(Locale('vi'));
    const polish = AppLocalizations(Locale('pl'));
    const dutch = AppLocalizations(Locale('nl'));
    const simplifiedChinese = AppLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    const traditionalChinese = AppLocalizations(
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );

    expect(
      german.text('Delete {count} holdings?', {'count': 3}),
      '3 Positionen löschen?',
    );
    expect(
      spanish.text('Date format ({example})', {'example': '24/09/26'}),
      'Formato de fecha (24/09/26)',
    );
    expect(
      brazilianPortuguese.text('Delete {count} holdings?', {'count': 3}),
      'Excluir 3 posições?',
    );
    expect(
      french.text('Delete {count} holdings?', {'count': 3}),
      'Supprimer 3 positions ?',
    );
    expect(
      japanese.text('Delete {count} holdings?', {'count': 3}),
      '3件の保有銘柄を削除しますか？',
    );
    expect(
      korean.text('Delete {count} holdings?', {'count': 3}),
      '보유 종목 3개를 삭제할까요?',
    );
    expect(
      arabic.text('Delete {count} holdings?', {'count': 3}),
      'حذف 3 مقتنيات؟',
    );
    expect(
      russian.text('Delete {count} holdings?', {'count': 3}),
      'Удалить позиции (3)?',
    );
    expect(
      indonesian.text('Delete {count} holdings?', {'count': 3}),
      'Hapus 3 kepemilikan?',
    );
    expect(
      turkish.text('Delete {count} holdings?', {'count': 3}),
      '3 varlık silinsin mi?',
    );
    const thai = AppLocalizations(Locale('th'));
    expect(
      thai.text('Delete {count} holdings?', {'count': 3}),
      'ลบการถือครอง 3 รายการหรือไม่?',
    );
    expect(
      vietnamese.text('Delete {count} holdings?', {'count': 3}),
      'Xóa 3 khoản nắm giữ?',
    );
    expect(
      polish.text('Delete {count} holdings?', {'count': 3}),
      'Usunąć pozycje (3)?',
    );
    expect(
      dutch.text('Delete {count} holdings?', {'count': 3}),
      '3 posities verwijderen?',
    );
    expect(
      simplifiedChinese.text('Delete {count} holdings?', {'count': 3}),
      '删除 3 个持仓？',
    );
    expect(
      traditionalChinese.text('Delete {count} holdings?', {'count': 3}),
      '刪除 3 筆持倉？',
    );
  });

  test('Chinese script selections resolve and persist independently', () async {
    final settings = SettingsState();
    await settings.initialized;

    await settings.setLanguageCode('zh-Hant');
    expect(
      settings.locale,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('languageCode'), 'zh-Hant');

    final reloaded = SettingsState();
    await reloaded.initialized;
    expect(
      reloaded.locale,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );

    expect(
      const AppLocalizations(Locale('zh', 'TW')).text('Settings'),
      '設定',
    );
    expect(
      AppLocalizations.resolveLocale(
        const Locale('zh', 'TW'),
        AppLocalizations.supportedLocales,
      ),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    expect(
      AppLocalizations.resolveLocale(
        const Locale('zh', 'CN'),
        AppLocalizations.supportedLocales,
      ),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
  });

  test('legacy Chinese language preference migrates to Simplified Chinese', () async {
    SharedPreferences.setMockInitialValues({
      'languageCode': 'zh',
      'visibleCurrencies': ['USD'],
      'displayCurrency': 'USD',
      'exchangeRate_USD': 1.0,
    });

    final settings = SettingsState();
    await settings.initialized;

    expect(settings.languageCode, 'zh-Hans');
    expect(
      settings.locale,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('languageCode'), 'zh-Hans');
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
