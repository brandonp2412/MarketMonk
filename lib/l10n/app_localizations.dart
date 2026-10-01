import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'translations.dart';

/// Localized user-facing copy for MarketMonk.
class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('de'),
    Locale('es'),
    Locale('fr'),
    Locale('pt', 'BR'),
    Locale('pt', 'PT'),
    Locale('pl'),
    Locale('nl'),
    Locale('it'),
    Locale('bn'),
    Locale('ur'),
    Locale('fa'),
    Locale('hi'),
    Locale('ar'),
    Locale('ru'),
    Locale('uk'),
    Locale('id'),
    Locale('ms'),
    Locale('tr'),
    Locale('th'),
    Locale('vi'),
    Locale('ja'),
    Locale('ko'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// Returns the localization instance attached to [context].
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(Locale('en'));
  }

  /// Stable identifier used for translation tables and persisted selection.
  static String localeKey(Locale locale) {
    if (locale.languageCode == 'pt') {
      return locale.countryCode == 'PT' ? 'pt-PT' : 'pt-BR';
    }
    if (locale.languageCode != 'zh') return locale.languageCode;
    final scriptCode = locale.scriptCode;
    if (scriptCode == 'Hant') return 'zh-Hant';
    if (scriptCode == 'Hans') return 'zh-Hans';
    if (const {'TW', 'HK', 'MO'}.contains(locale.countryCode)) return 'zh-Hant';
    return 'zh-Hans';
  }

  /// Resolves locale variants that Flutter cannot distinguish by language alone.
  static Locale resolveLocale(
    Locale? locale,
    Iterable<Locale> supportedLocales,
  ) {
    if (locale == null) return supportedLocales.first;
    final key = localeKey(locale);
    for (final supported in supportedLocales) {
      if (localeKey(supported) == key) return supported;
    }
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
    return supportedLocales.first;
  }

  /// Translates [source] and substitutes named brace placeholders.
  String text(
    String source, [
    Map<String, Object?> values = const <String, Object?>{},
  ]) {
    var result = appTranslations[localeKey(locale)]?[source] ?? source;
    for (final entry in values.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value.toString());
    }
    return result;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  /// Localized MarketMonk strings for this context.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
