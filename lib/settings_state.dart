import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'device_region_currency_stub.dart'
    if (dart.library.io) 'device_region_currency_io.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/background_network_coordinator.dart';
import 'package:market_monk/l10n/app_localizations.dart';
import 'package:market_monk/utils.dart';
import 'package:market_monk/logging.dart';
import 'package:market_monk/sqlite_settings.dart';

const _defaultSeedColor = Color(0xFF2B7A78);

int _colorToInt(Color color) =>
    ((color.a * 255).round() << 24) |
    ((color.r * 255).round() << 16) |
    ((color.g * 255).round() << 8) |
    (color.b * 255).round();

/// Currencies supported by the Frankfurter API (ECB data).
const supportedCurrencies = [
  'AUD',
  'BGN',
  'BRL',
  'CAD',
  'CHF',
  'CNY',
  'CZK',
  'DKK',
  'EUR',
  'GBP',
  'HKD',
  'HUF',
  'IDR',
  'ILS',
  'INR',
  'ISK',
  'JPY',
  'KRW',
  'MXN',
  'MYR',
  'NOK',
  'NZD',
  'PHP',
  'PLN',
  'RON',
  'SEK',
  'SGD',
  'THB',
  'TRY',
  'USD',
  'ZAR',
];

class SettingsState extends ChangeNotifier {
  final Future<http.Response> Function(Uri) _rateFetcher;
  final Future<String?> Function()? _localCurrencyDetector;
  final Map<String, Future<void>> _rateRefreshes = {};
  late final Future<void> initialized;

  ThemeMode theme = ThemeMode.system;
  String? languageCode;
  bool systemColors = false;
  bool curveLines = false;
  double curveSmoothness = 0.35;
  String dateFormat = 'd/M/yy';
  Color seedColor = _defaultSeedColor;
  String displayCurrency = 'USD';
  List<String> visibleCurrencies = ['USD'];
  bool showMarketClosed = false;
  bool pureBlack = false;
  bool hideDollarAmounts = false;

  SettingsState({
    Future<http.Response> Function(Uri)? rateFetcher,
    Future<String?> Function()? localCurrencyDetector,
  })  : _rateFetcher = rateFetcher ?? http.get,
        _localCurrencyDetector = localCurrencyDetector {
    initialized = init();
  }

  /// Locale selected by the user, or null to follow the device locale.
  Locale? get locale {
    final selectedLanguageCode = languageCode;
    if (selectedLanguageCode == null) return null;
    return AppLocalizations.supportedLocales.firstWhere(
      (locale) => AppLocalizations.localeKey(locale) == selectedLanguageCode,
    );
  }

  /// Returns the supported ISO 4217 currency for [locale], falling back to USD.
  static String currencyForLocale(Locale locale) {
    try {
      final code = NumberFormat.simpleCurrency(
        locale: locale.toString(),
      ).currencyName;
      if (code != null && supportedCurrencies.contains(code)) return code;
    } catch (_) {}
    return 'USD';
  }

  Future<String> _detectLocalCurrency() async {
    try {
      final detected = await (_localCurrencyDetector?.call() ??
          detectDeviceRegionCurrency());
      if (detected != null && supportedCurrencies.contains(detected)) {
        return detected;
      }
    } catch (_) {}

    return currencyForLocale(WidgetsBinding.instance.platformDispatcher.locale);
  }

  static List<String> _withUsd(Iterable<String> currencies) {
    final normalized = <String>[];
    for (final code in currencies) {
      if (code != 'USD' &&
          supportedCurrencies.contains(code) &&
          !normalized.contains(code)) {
        normalized.add(code);
      }
    }
    normalized.add('USD');
    return normalized;
  }

  static List<String> _defaultVisibleCurrencies(String homeCurrency) =>
      _withUsd([homeCurrency]);

  Future<void> init() async {
    final prefs = await SqliteSettings.getInstance();
    final themeStr = prefs.getString('theme');

    switch (themeStr) {
      case 'ThemeMode.system':
        theme = ThemeMode.system;
        break;
      case 'ThemeMode.dark':
        theme = ThemeMode.dark;
        break;
      case 'ThemeMode.light':
        theme = ThemeMode.light;
        break;
      default:
        theme = ThemeMode.system;
        break;
    }

    final savedLanguageCode = prefs.getString('languageCode');
    final migratedLanguageCode = savedLanguageCode == 'zh'
        ? 'zh-Hans'
        : savedLanguageCode == 'pt'
            ? 'pt-BR'
            : savedLanguageCode;
    final supportedLanguageCodes = AppLocalizations.supportedLocales
        .map(AppLocalizations.localeKey)
        .toSet();
    languageCode = supportedLanguageCodes.contains(migratedLanguageCode)
        ? migratedLanguageCode
        : null;
    if (savedLanguageCode == 'zh') {
      await prefs.setString('languageCode', 'zh-Hans');
    } else if (savedLanguageCode == 'pt') {
      await prefs.setString('languageCode', 'pt-BR');
    }

    systemColors = prefs.getBool('systemColors') ?? false;
    curveLines = prefs.getBool('curveLines') ?? false;
    curveSmoothness = prefs.getDouble('curveSmoothness') ?? 0.35;
    dateFormat = prefs.getString('dateFormat') ?? 'd/M/yy';
    final colorVal = prefs.getInt('seedColor');
    seedColor = colorVal != null ? Color(colorVal) : _defaultSeedColor;

    final homeCurrency = await _detectLocalCurrency();
    final savedCurrencies = prefs.getStringList('visibleCurrencies');
    visibleCurrencies = (savedCurrencies != null && savedCurrencies.isNotEmpty)
        ? _withUsd(savedCurrencies)
        : _defaultVisibleCurrencies(homeCurrency);
    if (savedCurrencies != null &&
        !listEquals(savedCurrencies, visibleCurrencies)) {
      await prefs.setStringList('visibleCurrencies', visibleCurrencies);
    }

    showMarketClosed = prefs.getBool('showMarketClosed') ?? false;
    pureBlack = prefs.getBool('pureBlack') ?? false;
    hideDollarAmounts = prefs.getBool('hideDollarAmounts') ?? false;
    maskCurrencyAmounts = hideDollarAmounts;

    displayCurrency = prefs.getString('displayCurrency') ?? homeCurrency;
    if (!visibleCurrencies.contains(displayCurrency)) {
      displayCurrency = visibleCurrencies.first;
    }
    final cachedRate = prefs.getDouble('exchangeRate_$displayCurrency');
    _applyRate(displayCurrency, cachedRate ?? 1.0);

    notifyListeners();
    talker.debug('Loaded application settings');

    runDetachedTask(
      _fetchAndApplyRate(displayCurrency),
      'Failed to refresh initial display exchange rate',
    );
  }

  void _applyRate(String currencyCode, double rate) {
    currency = NumberFormat.simpleCurrency(name: currencyCode);
    allRatesFromUsd[currencyCode] = rate;
  }

  Future<void> _fetchAndApplyRate(String currencyCode) {
    final existing = _rateRefreshes[currencyCode];
    if (existing != null) return existing;

    late final Future<void> future;
    future = _fetchAndApplyRateOnce(currencyCode).whenComplete(() {
      if (identical(_rateRefreshes[currencyCode], future)) {
        _rateRefreshes.removeWhere(
          (key, value) => key == currencyCode && identical(value, future),
        );
      }
    });
    _rateRefreshes[currencyCode] = future;
    return future;
  }

  Future<void> _fetchAndApplyRateOnce(String currencyCode) async {
    if (currencyCode == 'USD') {
      allRatesFromUsd['USD'] = 1.0;
      final prefs = await SqliteSettings.getInstance();
      await prefs.setDouble('exchangeRate_USD', 1.0);
      if (displayCurrency == currencyCode) {
        _applyRate('USD', 1.0);
        notifyListeners();
      }
      return;
    }
    try {
      final rate = await backgroundNetworkCoordinator.coalesce<double?>(
        RequestCategory.fxRate,
        currencyCode,
        () async {
          final uri = Uri.parse(
            'https://api.frankfurter.app/latest?from=USD&to=$currencyCode',
          );
          final response = await _rateFetcher(uri);
          if (response.statusCode != 200) return null;
          final data = json.decode(response.body) as Map<String, dynamic>;
          final rates = data['rates'] as Map<String, dynamic>;
          return (rates[currencyCode] as num).toDouble();
        },
      );
      if (rate != null) {
        allRatesFromUsd[currencyCode] = rate;
        final prefs = await SqliteSettings.getInstance();
        await prefs.setDouble('exchangeRate_$currencyCode', rate);
        if (displayCurrency == currencyCode) {
          _applyRate(currencyCode, rate);
          notifyListeners();
        }
        talker.info('Refreshed display exchange rate');
      }
    } catch (error, stackTrace) {
      talker.handle(
        error,
        stackTrace,
        'Failed to refresh display exchange rate',
      );
    }
  }

  /// Persists the date pattern used throughout the interface.
  Future<void> setDateFormat(String value) async {
    dateFormat = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setString('dateFormat', value);
  }

  /// Persists whether charts interpolate between data points.
  Future<void> setCurveLines(bool value) async {
    curveLines = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setBool('curveLines', value);
  }

  /// Persists the dark-theme background preference.
  Future<void> setPureBlack(bool value) async {
    pureBlack = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setBool('pureBlack', value);
  }

  /// Persists whether monetary values are masked throughout the interface.
  Future<void> setHideDollarAmounts(bool value) async {
    hideDollarAmounts = value;
    maskCurrencyAmounts = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setBool('hideDollarAmounts', value);
  }

  /// Persists whether closed-market indicators are shown.
  Future<void> setShowMarketClosed(bool value) async {
    showMarketClosed = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setBool('showMarketClosed', value);
  }

  /// Persists the interpolation strength used by charts.
  Future<void> setCurveSmoothness(double value) async {
    curveSmoothness = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setDouble('curveSmoothness', value);
  }

  /// Persists whether the theme follows system-provided colors.
  Future<void> setSystemColors(bool value) async {
    systemColors = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setBool('systemColors', value);
  }

  /// Persists the selected theme before reporting completion.
  Future<void> setTheme(ThemeMode value) async {
    theme = value;
    notifyListeners();
    await (await SqliteSettings.getInstance())
        .setString('theme', value.toString());
  }

  Future<void> setLanguageCode(String? value) async {
    final isSupported = value == null ||
        AppLocalizations.supportedLocales.any(
          (locale) => AppLocalizations.localeKey(locale) == value,
        );
    if (!isSupported) return;

    languageCode = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    if (value == null) {
      await prefs.remove('languageCode');
    } else {
      await prefs.setString('languageCode', value);
    }
  }

  /// Persists the custom color used to generate the app theme.
  Future<void> setSeedColor(Color value) async {
    seedColor = value;
    notifyListeners();
    final prefs = await SqliteSettings.getInstance();
    await prefs.setInt('seedColor', _colorToInt(value));
  }

  Future<void> setVisibleCurrencies(List<String> currencies) async {
    visibleCurrencies = _withUsd(currencies);
    final prefs = await SqliteSettings.getInstance();
    await prefs.setStringList('visibleCurrencies', visibleCurrencies);
    if (!visibleCurrencies.contains(displayCurrency)) {
      await _setDisplayCurrency(visibleCurrencies.first, prefs);
      return;
    }
    notifyListeners();
  }

  Future<void> setDisplayCurrency(String code) async {
    final prefs = await SqliteSettings.getInstance();
    await _setDisplayCurrency(code, prefs);
  }

  Future<void> _setDisplayCurrency(
    String code,
    SqliteSettings prefs,
  ) async {
    displayCurrency = code;
    final cachedRate = prefs.getDouble('exchangeRate_$code');
    _applyRate(code, cachedRate ?? allRatesFromUsd[code] ?? 1.0);
    notifyListeners();
    await prefs.setString('displayCurrency', code);
    runDetachedTask(
      _fetchAndApplyRate(code),
      'Failed to refresh display exchange rate',
    );
  }

  int tradesVersion = 0;
  bool syncInProgress = false;
  int syncCompleted = 0;
  int syncTotal = 0;
  int syncFailed = 0;
  String? syncingSymbol;
  String? lastSyncError;
  Future<void>? _activeTickerSync;

  double? get syncProgress => syncTotal == 0 ? null : syncCompleted / syncTotal;

  /// Increments [tradesVersion] to signal that portfolio data has changed.
  void notifyTradesImported() {
    tradesVersion++;
    notifyListeners();
    talker.debug('Notified listeners of a trade-data change');
  }

  /// Synchronizes [symbols] sequentially while exposing progress to the UI.
  /// Requests made during an active sync are queued and run afterwards.
  Future<void> syncTickers(
    Iterable<String> symbols,
    Future<void> Function(String symbol) sync,
  ) async {
    while (_activeTickerSync != null) {
      await _activeTickerSync;
    }

    final future = _runTickerSync(symbols, sync);
    _activeTickerSync = future;
    try {
      await future;
    } finally {
      if (identical(_activeTickerSync, future)) _activeTickerSync = null;
    }
  }

  Future<void> _runTickerSync(
    Iterable<String> symbols,
    Future<void> Function(String symbol) sync,
  ) async {
    final uniqueSymbols = symbols.toSet().toList()..sort();
    syncInProgress = true;
    syncCompleted = 0;
    syncTotal = uniqueSymbols.length;
    syncFailed = 0;
    syncingSymbol = null;
    lastSyncError = null;
    notifyListeners();

    for (final symbol in uniqueSymbols) {
      syncingSymbol = symbol;
      notifyListeners();
      try {
        await sync(symbol);
      } catch (error, stackTrace) {
        syncFailed++;
        lastSyncError = error.toString();
        talker.handle(error, stackTrace, 'Ticker sync failed for $symbol');
      } finally {
        syncCompleted++;
        notifyListeners();
      }
    }

    syncingSymbol = null;
    syncInProgress = false;
    tradesVersion++;
    notifyListeners();
    talker.info(
      'Ticker sync completed: $syncCompleted/$syncTotal, $syncFailed failed',
    );
  }
}
