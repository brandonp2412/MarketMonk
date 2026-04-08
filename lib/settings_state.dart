import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:market_monk/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _defaultSeedColor = Color(0xFF2B7A78);

int _colorToInt(Color c) =>
    ((c.a * 255).round() << 24) |
    ((c.r * 255).round() << 16) |
    ((c.g * 255).round() << 8) |
    (c.b * 255).round();

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
  ThemeMode theme = ThemeMode.system;
  bool systemColors = false;
  bool curveLines = false;
  double curveSmoothness = 0.35;
  String dateFormat = 'd/M/yy';
  Color seedColor = _defaultSeedColor;
  String displayCurrency = 'USD';

  SettingsState() {
    init();
  }

  init() async {
    final prefs = await SharedPreferences.getInstance();
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

    systemColors = prefs.getBool('systemColors') ?? false;
    curveLines = prefs.getBool('curveLines') ?? false;
    curveSmoothness = prefs.getDouble('curveSmoothness') ?? 0.35;
    dateFormat = prefs.getString('dateFormat') ?? 'd/M/yy';
    final colorVal = prefs.getInt('seedColor');
    seedColor = colorVal != null ? Color(colorVal) : _defaultSeedColor;

    displayCurrency = prefs.getString('displayCurrency') ?? 'USD';
    final cachedRate = prefs.getDouble('exchangeRate_$displayCurrency');
    _applyRate(displayCurrency, cachedRate ?? 1.0);

    notifyListeners();

    // Refresh exchange rate in background
    _fetchAndApplyRate(displayCurrency);
  }

  void _applyRate(String currencyCode, double rate) {
    currency = NumberFormat.simpleCurrency(name: currencyCode);
    exchangeRate = rate;
  }

  Future<void> _fetchAndApplyRate(String currencyCode) async {
    if (currencyCode == 'USD') {
      _applyRate('USD', 1.0);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('exchangeRate_USD', 1.0);
      notifyListeners();
      return;
    }
    try {
      final uri = Uri.parse(
        'https://api.frankfurter.app/latest?from=USD&to=$currencyCode',
      );
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rates = data['rates'] as Map<String, dynamic>;
        final rate = (rates[currencyCode] as num).toDouble();
        _applyRate(currencyCode, rate);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('exchangeRate_$currencyCode', rate);
        notifyListeners();
      }
    } catch (_) {
      // Keep using cached rate on network failure
    }
  }

  void setDateFormat(String value) async {
    dateFormat = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('dateFormat', value);
  }

  void setCurveLines(bool value) async {
    curveLines = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('curveLines', value);
  }

  void setCurveSmoothness(double value) async {
    curveSmoothness = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble('curveSmoothness', value);
  }

  void setSystemColors(bool value) async {
    systemColors = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('systemColors', value);
  }

  void setTheme(ThemeMode value) {
    theme = value;
    notifyListeners();
  }

  void setSeedColor(Color value) async {
    seedColor = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    prefs.setInt('seedColor', _colorToInt(value));
  }

  void setDisplayCurrency(String code) async {
    displayCurrency = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('displayCurrency', code);
    final cachedRate = prefs.getDouble('exchangeRate_$code');
    if (cachedRate != null) _applyRate(code, cachedRate);
    await _fetchAndApplyRate(code);
  }
}
